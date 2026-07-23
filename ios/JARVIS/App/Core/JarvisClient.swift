//
//  JarvisClient.swift
//  JARVIS
//
//  Actor that owns all JSON+SSE lifecycle. No data races on streaming deltas.
//

import Foundation
import LDSwiftEventSource
import Observation

public actor JarvisClient {
    public struct Config: Sendable {
        public let gatewayURL: URL
        public let bearerToken: String
        public init(gatewayURL: URL, bearerToken: String) {
            self.gatewayURL = gatewayURL
            self.bearerToken = bearerToken
        }
    }

    private var config: Config
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(config: Config) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 600
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)
        self.decoder = JSONDecoder()
    }

    public func updateConfig(_ config: Config) {
        self.config = config
    }

    // MARK: - JSON requests

    private func makeRequest(_ api: JarvisAPI, body: Encodable? = nil) -> URLRequest {
        let bodyData: Data?
        if let body = body {
            do {
                let enc = JSONEncoder()
                bodyData = try enc.encode(AnyEncodable(body))
            } catch {
                bodyData = nil
            }
        } else {
            bodyData = nil
        }
        return api.urlRequest(base: config.gatewayURL, token: config.bearerToken, body: bodyData)
    }

    public func getJSON<R: Decodable>(_ api: JarvisAPI) async throws -> R {
        let req = makeRequest(api)
        JarvisLog.network.debug("GET \(api.url(base: self.config.gatewayURL).absoluteString, privacy: .public)")
        do {
            let (data, response) = try await session.data(for: req)
            try check(response: response, data: data)
            return try decoder.decode(R.self, from: data)
        } catch let err as APIError {
            throw err
        } catch let err as URLError where err.code == .notConnectedToInternet
                                || err.code == .networkConnectionLost
                                || err.code == .cannotConnectToHost {
            throw APIError.offline
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    public func postJSON<R: Decodable>(_ api: JarvisAPI, body: Encodable) async throws -> R {
        let req = makeRequest(api, body: body)
        JarvisLog.network.debug("POST \(api.url(base: self.config.gatewayURL).absoluteString, privacy: .public)")
        do {
            let (data, response) = try await session.data(for: req)
            try check(response: response, data: data)
            return try decoder.decode(R.self, from: data)
        } catch let err as APIError {
            throw err
        } catch let err as URLError where err.code == .notConnectedToInternet
                                || err.code == .networkConnectionLost
                                || err.code == .cannotConnectToHost {
            throw APIError.offline
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    public func postJSONDiscard(_ api: JarvisAPI, body: Encodable) async throws {
        let req = makeRequest(api, body: body)
        JarvisLog.network.debug("POST \(api.url(base: self.config.gatewayURL).absoluteString, privacy: .public)")
        do {
            let (_, response) = try await session.data(for: req)
            try check(response: response, data: Data())
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    private func check(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("no http response")
        }
        if http.statusCode == 401 {
            throw APIError.unauthorized
        }
        if (200...299).contains(http.statusCode) {
            return
        }
        let bodyStr = String(data: data, encoding: .utf8) ?? ""
        if http.statusCode >= 500 {
            throw APIError.upstream(message: bodyStr)
        }
        throw APIError.http(status: http.statusCode, body: bodyStr)
    }

    // MARK: - High-level endpoints

    public func ping() async throws {
        do {
            let _: [String: AnyCodable] = try await getJSON(.health)
        } catch APIError.http(401, _) {
            throw APIError.unauthorized
        }
    }

    public func fetchSessions(includeArchived: Bool = false) async throws -> [Session] {
        let api = JarvisAPI.sessions
        let resp: SessionListResponse = try await getJSON(api)
        return resp.sessions
    }

    public func fetchSessionDetail(id: String) async throws -> SessionDetailResponse {
        try await getJSON(.session(id: id, messages: true))
    }

    public func newSession(_ req: NewSessionRequest) async throws -> Session {
        struct Wrap: Decodable { let session: Session }
        let wrap: Wrap = try await postJSON(.newSession, body: req)
        return wrap.session
    }

    public func renameSession(sessionID: String, to title: String) async throws {
        try await postJSONDiscard(.renameSession, body: RenameSessionRequest(session_id: sessionID, title: title))
    }

    public func deleteSession(sessionID: String, worktreeRemove: Bool = false) async throws {
        try await postJSONDiscard(.deleteSession, body: DeleteSessionRequest(session_id: sessionID, worktree_remove: worktreeRemove))
    }

    public func setSessionPinned(sessionID: String, pinned: Bool) async throws {
        try await postJSONDiscard(.pinSession, body: PinSessionRequest(session_id: sessionID, pinned: pinned))
    }

    public func setSessionArchived(sessionID: String, archived: Bool) async throws {
        try await postJSONDiscard(.archiveSession, body: ArchiveSessionRequest(session_id: sessionID, archived: archived))
    }

    public func startTurn(_ req: ChatStartRequest) async throws -> ChatStartResponse {
        try await postJSON(.chatStart, body: req)
    }

    public func cancelStream(_ streamID: String) async throws {
        let req = makeRequest(.chatCancel(streamID: streamID))
        let (_, response) = try await session.data(for: req)
        try check(response: response, data: Data())
    }

    public func fetchApprovals() async throws -> [ApprovalRecord] {
        let response: ApprovalListResponse = try await getJSON(.approvals)
        return response.approvals
    }

    public func decideApproval(id: String, decision: String) async throws -> ApprovalRecord {
        try await postJSON(
            .approvalDecision(id: id),
            body: ApprovalDecisionRequest(decision: decision)
        )
    }

    // MARK: - SSE

    /// Opens the SSE stream for a `stream_id` and yields parsed `SSEEvent`s.
    /// Auto-reconnects on disconnect with `after_event_id=<lastId>` if the caller
    /// provides `lastEventID`.
    public func stream(
        streamID: String,
        lastEventID: String? = nil,
        maxReconnects: Int = 30
    ) -> AsyncThrowingStream<SSEEventEnvelope, Error> {
        AsyncThrowingStream { continuation in
            let url = JarvisAPI.chatStream(streamID: streamID, afterEventID: lastEventID)
                .url(base: config.gatewayURL)
            var req = URLRequest(url: url)
            req.setValue("Bearer \(config.bearerToken)", forHTTPHeaderField: "Authorization")
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 0    // SSE — no overall timeout

            JarvisLog.sse.info("connecting stream id=\(streamID, privacy: .public) afterEventID=\(lastEventID ?? "nil", privacy: .public)")

            let handler = StreamHandler(
                continuation: continuation,
                bearerToken: config.bearerToken,
                gatewayURL: config.gatewayURL,
                maxReconnects: maxReconnects
            )
            var cfg = EventSource.Config(handler: handler, url: url)
            cfg.headers = [
                "Authorization": "Bearer \(config.bearerToken)",
                "Accept": "text/event-stream"
            ]
            cfg.lastEventId = lastEventID ?? ""
            cfg.reconnectTime = 1.0
            cfg.maxReconnectTime = 30.0
            let eventSource = EventSource(config: cfg)
            handler.eventSource = eventSource
            continuation.onTermination = { @Sendable _ in
                Task { await handler.cancel() }
            }
            eventSource.start()
        }
    }
}

// MARK: - StreamHandler

/// Wraps the EventSource EventHandler with reconnect bookkeeping
/// (lastEventID cursor + reconnect budget). The library auto-injects
/// `Last-Event-Id` on every reconnect from parsed event IDs.
private final class StreamHandler: EventHandler, @unchecked Sendable {
    let continuation: AsyncThrowingStream<SSEEventEnvelope, Error>.Continuation
    let bearerToken: String
    let gatewayURL: URL
    let maxReconnects: Int

    private var reconnectCount = 0
    private var lastEventID: String?
    private var finished = false
    private let lock = NSLock()
    var eventSource: EventSource!

    init(
        continuation: AsyncThrowingStream<SSEEventEnvelope, Error>.Continuation,
        bearerToken: String,
        gatewayURL: URL,
        maxReconnects: Int
    ) {
        self.continuation = continuation
        self.bearerToken = bearerToken
        self.gatewayURL = gatewayURL
        self.maxReconnects = maxReconnects
    }

    func onOpened() {
        JarvisLog.sse.debug("opened")
    }

    func onClosed() {
        JarvisLog.sse.debug("closed")
    }

    func onMessage(eventType: String, messageEvent: MessageEvent) {
        if !messageEvent.lastEventId.isEmpty {
            lock.lock(); lastEventID = messageEvent.lastEventId; lock.unlock()
        }
        let parsed = SSEParser.parse(
            eventName: eventType,
            data: messageEvent.data,
            id: messageEvent.lastEventId
        )
        guard let evt = parsed else { return }
        continuation.yield(SSEEventEnvelope(event: evt, lastEventID: lastEventID))
        if case .streamEnd = evt { finish(throwing: nil) }
    }

    func onComment(comment: String) {
        // 5s heartbeats — ignored.
    }

    func onError(error: Error) {
        JarvisLog.sse.warning("error: \(error.localizedDescription, privacy: .public)")
        if finished { return }
        // Don't immediately fail — LDSwiftEventSource auto-reconnects by default.
        // Only terminate if we've burned through our reconnect budget.
        reconnectCount += 1
        if reconnectCount > maxReconnects {
            finish(throwing: APIError.transport(error.localizedDescription))
            eventSource?.stop()
        }
    }

    @MainActor
    func cancel() {
        finish(throwing: nil)
        eventSource?.stop()
    }

    private func finish(throwing error: Error?) {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        if let error = error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}

// MARK: - Event envelope (event + cursor)

public struct SSEEventEnvelope: Sendable {
    public let event: SSEEvent
    public let lastEventID: String?
    public init(event: SSEEvent, lastEventID: String?) {
        self.event = event
        self.lastEventID = lastEventID
    }
}

// MARK: - AnyEncodable (private to JarvisClient)

/// Erases the generic parameter when calling `JSONEncoder` with `Encodable` types
/// declared in `JarvisModels.swift`.
private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
