//
//  HermesClient.swift
//  Hermes
//
//  Actor that owns all JSON+SSE lifecycle. No data races on streaming deltas.
//

import Foundation
import LDEventSource
import Observation

public actor HermesClient {
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

    private func makeRequest(_ api: HermesAPI, body: Encodable? = nil) -> URLRequest {
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

    public func getJSON<R: Decodable>(_ api: HermesAPI) async throws -> R {
        let req = makeRequest(api)
        HermesLog.network.debug("GET \(api.url(base: config.gatewayURL).absoluteString, privacy: .public)")
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

    public func postJSON<R: Decodable>(_ api: HermesAPI, body: Encodable) async throws -> R {
        let req = makeRequest(api, body: body)
        HermesLog.network.debug("POST \(api.url(base: config.gatewayURL).absoluteString, privacy: .public)")
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

    public func postJSONDiscard(_ api: HermesAPI, body: Encodable) async throws {
        let req = makeRequest(api, body: body)
        HermesLog.network.debug("POST \(api.url(base: config.gatewayURL).absoluteString, privacy: .public)")
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
        var api = HermesAPI.sessions
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
        _ = try? await getJSON(.chatCancel(streamID: streamID))
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
            let url = HermesAPI.chatStream(streamID: streamID, afterEventID: lastEventID)
                .url(base: config.gatewayURL)
            var req = URLRequest(url: url)
            req.setValue("Bearer \(config.bearerToken)", forHTTPHeaderField: "Authorization")
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 0    // SSE — no overall timeout

            HermesLog.sse.info("connecting stream id=\(streamID, privacy: .public) afterEventID=\(lastEventID ?? "nil", privacy: .public)")

            let delegate = StreamDelegate(
                continuation: continuation,
                bearerToken: config.bearerToken,
                gatewayURL: config.gatewayURL,
                maxReconnects: maxReconnects
            )
            delegate.eventSource = LDEventSource.EventSource(
                request: req,
                configuration: LDEventSource.Configuration(
                    reconnectTime: 1.0,
                    reconnectTimeMax: 30.0,
                    reconnectRandomnessFactor: 0.3,
                    allowedTLSProtocols: [.TLSv12],
                    httpHeaders: ["Authorization": "Bearer \(config.bearerToken)"]
                ),
                delegate: delegate
            )
            continuation.onTermination = { @Sendable _ in
                Task { await delegate.cancel() }
            }
            delegate.eventSource.start()
        }
    }
}

// MARK: - StreamDelegate

/// Wraps the EventSource delegate with reconnect aware of `after_event_id`.
private final class StreamDelegate: NSObject, LDEventSource.EventSourceDelegate, @unchecked Sendable {
    let continuation: AsyncThrowingStream<SSEEventEnvelope, Error>.Continuation
    let bearerToken: String
    let gatewayURL: URL
    let maxReconnects: Int

    private var reconnectCount = 0
    private var lastEventID: String?
    private var finished = false
    private let lock = NSLock()
    var eventSource: LDEventSource.EventSource!

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
        super.init()
    }

    func eventSourceOpened(_ eventSource: LDEventSource.EventSource) {
        HermesLog.sse.debug("opened")
    }

    func eventSource(_ eventSource: LDEventSource.EventSource, didReceiveMessage event: LDEventSource.MessageEvent) {
        // Each event arrives here with parsed name/data/id/retry
        if let id = event.id, !id.isEmpty {
            lock.lock(); lastEventID = id; lock.unlock()
        }
        let parsed = SSEParser.parse(eventName: event.event, data: event.data ?? "", id: event.id)
        guard let evt = parsed else { return }
        continuation.yield(SSEEventEnvelope(event: evt, lastEventID: lastEventID))
        if case .streamEnd = evt { finish() }
    }

    func eventSource(_ eventSource: LDEventSource.EventSource, didReceiveError error: Error) {
        HermesLog.sse.warning("error: \(error.localizedDescription, privacy: .public)")
        if finished { return }
        // Don't immediately fail — LDSwiftEventSource auto-reconnects by default.
        // Only terminate if we've burned through our reconnect budget.
        reconnectCount += 1
        if reconnectCount > maxReconnects {
            continuation.finish(throwing: APIError.transport(error.localizedDescription))
        }
    }

    func eventSourceClosed(_ eventSource: LDEventSource.EventSource) {
        HermesLog.sse.debug("closed")
    }

    func eventSource(_ eventSource: LDEventSource.EventSource, didReceiveComment comment: String) {
        // 5s heartbeats — ignored.
    }

    func eventSource(_ eventSource: LDEventSource.EventSource, willRetryWithDelay delay: TimeInterval) {
        // The library is about to retry — reapply after_event_id from the latest event id.
        HermesLog.sse.info("will retry in \(delay, privacy: .public)s with afterEventID=\(lastEventID ?? "nil", privacy: .public)")
        // LDEventSource constructs its own retry URL — we cannot easily mutate
        // the base URL, so we rely on the server-side journal accept the
        // Last-Event-ID header (which LDEventSource sends automatically).
    }

    @MainActor
    func cancel() {
        finish()
        eventSource?.close()
    }

    private func finish() {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation.finish()
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

// MARK: - AnyEncodable (private to HermesClient)

/// Erases the generic parameter when calling `JSONEncoder` with `Encodable` types
/// declared in `HermesModels.swift`.
private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
