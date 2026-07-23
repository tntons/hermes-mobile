//
//  ConversationViewModel.swift
//  Hermes
//
//  Owns the in-memory message list for one conversation, plus the active stream.
//

import Foundation
import Observation

@Observable
@MainActor
public final class ConversationViewModel {
    public private(set) var sessionID: String
    public var title: String
    public var messages: [ChatMessage] = []
    public var composerText: String = ""
    public var isStreaming: Bool = false
    public var isLoadingHistory: Bool = false
    public var historyErrorMessage: String?
    public var errorMessage: String?
    public var titleDraft: String = ""

    private var client: HermesClient?
    private var isMock = false
    private var pendingInitialMessage: String?
    private var initialMessageSubmitted = false
    private var streamTask: Task<Void, Never>?
    private var tokenFlushTask: Task<Void, Never>?
    private var pendingTokens: String = ""

    /// Saved across reconnects.
    private var currentStreamID: String?
    private var lastEventID: String?

    public init(sessionID: String, title: String, initialMessage: String? = nil) {
        self.sessionID = sessionID
        self.title = title
        self.titleDraft = title
        self.pendingInitialMessage = initialMessage
    }

    public func bootstrap(config: APIConfig) async {
        if config.isMock {
            isMock = true
            messages = MockData.messages(for: sessionID)
            isLoadingHistory = false
            return
        }
        guard config.isConfigured,
              let url = config.gatewayURL,
              let token = config.bearerToken
        else { return }
        let c = HermesClient(config: .init(gatewayURL: url, bearerToken: token))
        self.client = c

        // Show cached history immediately.
        let cached = HermesDAO.cachedMessages(sessionID: sessionID)
        if !cached.isEmpty {
            messages = cached.map {
                ChatMessage(
                    role: Message.Role(rawValue: $0.role) ?? .user,
                    text: $0.text,
                    reasoning: $0.reasoning ?? "",
                    terminal: $0.isFinal ? .success : nil,
                    timestamp: $0.timestamp,
                    isFinal: $0.isFinal
                )
            }
        }

        // Refresh from server.
        await refreshHistory()
    }

    public func refreshHistory() async {
        if isMock { return }
        guard let client = client else {
            isLoadingHistory = false
            return
        }
        if messages.isEmpty {
            isLoadingHistory = true
        }
        defer { isLoadingHistory = false }
        do {
            let detail = try await client.fetchSessionDetail(id: sessionID)
            // Replace messages where their content differs from cache, preserving
            // any currently-streaming assistant placeholder at the tail.
            var loaded: [ChatMessage] = detail.messages.map { m in
                var mut = ChatMessage(
                    role: m.role,
                    text: m.textRepresentation,
                    reasoning: m.reasoning ?? "",
                    terminal: m.isFinal ? .success : nil,
                    timestamp: Date(timeIntervalSince1970: m.timestamp),
                    isFinal: m.isFinal
                )
                if let calls = m.tool_calls {
                    mut.toolCalls = calls
                }
                return mut
            }
            // Merge streaming placeholder for the active assistant message.
            if let last = messages.last, last.role == .assistant, !last.isFinal {
                loaded.append(last)
            }
            messages = loaded
            HermesDAO.upsertMessages(sessionID: sessionID, messages: detail.messages)
            title = detail.session.title
            titleDraft = detail.session.title
            historyErrorMessage = nil
        } catch {
            // Don't clear — keep the cache and make the refresh failure visible.
            historyErrorMessage = error.localizedDescription
            HermesLog.sse.debug("history refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Sending

    public func sendInitialMessageIfNeeded() async {
        guard !initialMessageSubmitted,
              let initialMessage = pendingInitialMessage,
              !initialMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isStreaming,
              isMock || client != nil
        else { return }

        initialMessageSubmitted = true
        pendingInitialMessage = nil
        composerText = initialMessage
        await send()
    }

    public func send() async {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        await send(text: text, appendingUserMessage: true)
    }

    /// Re-run the latest assistant turn using the existing user prompt.
    /// Remove the previous exchange first so the refreshed transcript contains
    /// one copy of the resent prompt and one regenerated response.
    public func regenerateLastResponse() async {
        guard !isStreaming,
              let assistantIndex = messages.lastIndex(where: { $0.role == .assistant && $0.isFinal }),
              assistantIndex == messages.count - 1,
              let userIndex = messages[..<assistantIndex].lastIndex(where: { $0.role == .user })
        else { return }

        let text = messages[userIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.removeSubrange(userIndex...assistantIndex)
        await send(text: text, appendingUserMessage: true)
    }

    private func send(text: String, appendingUserMessage: Bool) async {
        if isMock {
            await sendMock(text: text, appendingUserMessage: appendingUserMessage)
            return
        }
        guard let client = client else { return }
        guard !isStreaming else { return }
        if appendingUserMessage {
            composerText = ""
        }
        HapticManager.play(.soft)
        if appendingUserMessage {
            messages.append(.user(text))
        }
        // Append placeholder assistant message.
        let assistant = ChatMessage.assistant()
        messages.append(assistant)
        let placeholderID = assistant.id

        isStreaming = true
        do {
            let req = ChatStartRequest(
                session_id: sessionID,
                message: text,
                profile: KeychainStore.shared.profile
            )
            let start = try await client.startTurn(req)
            if let err = start.error {
                throw APIError.upstream(message: err)
            }
            currentStreamID = start.stream_id
            HermesDAO.recordCursor(streamID: start.stream_id, sessionID: sessionID)

            await consume(streamID: start.stream_id, lastEventID: nil, on: placeholderID)
        } catch {
            isStreaming = false
            errorMessage = error.localizedDescription
            HapticManager.play(.error)
            if let idx = messages.firstIndex(where: { $0.id == placeholderID }) {
                messages[idx].terminal = .error(error.localizedDescription)
                messages[idx].isFinal = true
            }
        }
    }

    public func cancelStream() async {
        if isMock {
            isStreaming = false
            return
        }
        guard let client = client, let sid = currentStreamID else { return }
        try? await client.cancelStream(sid)
        streamTask?.cancel()
        tokenFlushTask?.cancel()
    }

    /// Resume an in-flight run after returning from background.
    public func resumeIfNeeded() async {
        if isMock { return }
        guard let client = client else { return }
        let open = HermesDAO.openCursors().filter { $0.sessionID == sessionID }
        guard let cursor = open.first else { return }
        currentStreamID = cursor.streamID
        lastEventID = cursor.lastEventID

        // Append an "assistant" placeholder for visual continuity.
        if messages.last?.role != .assistant || messages.last?.isFinal == true {
            messages.append(.assistant())
        }
        isStreaming = true
        await consume(streamID: cursor.streamID, lastEventID: cursor.lastEventID, on: messages.last!.id)
    }

    private func sendMock(text: String, appendingUserMessage: Bool) async {
        guard !text.isEmpty, !isStreaming else { return }
        if appendingUserMessage {
            composerText = ""
        }
        HapticManager.play(.soft)
        if appendingUserMessage {
            messages.append(.user(text))
        }
        let assistant = ChatMessage.assistant()
        messages.append(assistant)
        isStreaming = true

        try? await Task.sleep(nanoseconds: 250_000_000)
        guard let index = messages.firstIndex(where: { $0.id == assistant.id }) else { return }
        messages[index].text = "Demo reply: I received \"\(text)\". Connect Hermes later to talk to a real backend."
        messages[index].terminal = .success
        messages[index].isFinal = true
        isStreaming = false
        HapticManager.play(.success)
    }

    // MARK: - SSE consumer

    private func consume(streamID: String, lastEventID: String?, on assistantID: UUID) async {
        streamTask?.cancel()
        guard let client = client else { return }

        let stream = await client.stream(streamID: streamID, lastEventID: lastEventID)
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await envelope in stream {
                    if Task.isCancelled { break }
                    self.handle(envelope.event, envelope: envelope, assistantID: assistantID)
                    if let term = SSEParser.terminalState(of: envelope.event) {
                        self.finalizeStream(terminal: term, assistantID: assistantID)
                        return
                    }
                }
                self.finalizeStream(terminal: .success, assistantID: assistantID)
            } catch {
                self.errorMessage = error.localizedDescription
                self.finalizeStream(terminal: .error(error.localizedDescription), assistantID: assistantID)
            }
        }
        await streamTask?.value
    }

    private func handle(_ event: SSEEvent, envelope: SSEEventEnvelope, assistantID: UUID) {
        lastEventID = envelope.lastEventID
        if let sid = currentStreamID, let eid = envelope.lastEventID {
            HermesDAO.recordCursor(streamID: sid, sessionID: sessionID, lastEventID: eid)
        }
        guard let idx = messages.firstIndex(where: { $0.id == assistantID }) else { return }

        switch event {
        case .token(let text):
            queueToken(text)
        case .reasoning(let text):
            messages[idx].reasoning.append(text)
        case .interimAssistant(let text, let alreadyStreamed):
            if !alreadyStreamed { queueToken(text) }
        case .tool(let t):
            messages[idx].pendingTool = ToolCall(name: t.name, args: t.args, preview: t.preview)
        case .toolComplete(let t):
            // Promote pending tool call into the permanent array.
            if let pending = messages[idx].pendingTool {
                messages[idx].toolCalls.append(ToolCall(
                    name: pending.name,
                    args: pending.args ?? t.args,
                    preview: t.preview,
                    duration: t.duration,
                    is_error: t.is_error
                ))
            } else {
                messages[idx].toolCalls.append(ToolCall(
                    name: t.name,
                    args: t.args,
                    preview: t.preview,
                    duration: t.duration,
                    is_error: t.is_error
                ))
            }
            messages[idx].pendingTool = nil
        case .approval(let a):
            messages[idx].approval = a
        case .clarify(let c):
            // v1: render as a pseudo tool-call so the user sees it.
            messages[idx].toolCalls.append(ToolCall(
                name: "clarify",
                args: AnyCodable(["question": c.question]),
                preview: c.question,
                duration: nil,
                is_error: nil
            ))
        case .compressing:
            messages[idx].toolCalls.append(ToolCall(name: "compress", preview: "Compressing context…"))
        case .compressed(let c):
            if let n = c.new_session_id { self.sessionID = n }
        case .warning(let w):
            messages[idx].toolCalls.append(ToolCall(name: "warning", preview: "\(w.type ?? "info"): \(w.message)"))
        case .metering, .contextStatus, .todoState, .stateSaved, .goal, .goalContinue, .keepAlive:
            break
        case .done, .streamEnd, .cancel, .appError:
            break  // handled by terminal caller
        }
    }

    // MARK: - Token coalescing (≈15 Hz)

    private func queueToken(_ delta: String) {
        guard !delta.isEmpty else { return }
        pendingTokens.append(delta)
        if tokenFlushTask == nil {
            tokenFlushTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 66_000_000)   // ~15 Hz
                    guard let self else { return }
                    let chunk = self.pendingTokens
                    self.pendingTokens = ""
                    if !chunk.isEmpty {
                        if let idx = self.messages.indices.last, self.messages[idx].role == .assistant {
                            self.messages[idx].text.append(chunk)
                        }
                    }
                    tokenFlushTask = nil
                    return
                }
            }
        }
    }

    private func finalizeStream(terminal: TerminalState, assistantID: UUID) {
        isStreaming = false
        // Flush pending tokens before finalizing.
        if !pendingTokens.isEmpty,
           let idx = messages.firstIndex(where: { $0.id == assistantID }) {
            messages[idx].text.append(pendingTokens)
            pendingTokens = ""
        }
        if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
            messages[idx].terminal = terminal
            messages[idx].isFinal = true
            HermesDAO.appendMessage(messages[idx], sessionID: sessionID)
        }
        if let sid = currentStreamID {
            let str: String = {
                switch terminal { case .success: return "success"; case .cancelled: return "cancelled"; case .error(let m): return "error: \(m)" }
            }()
            HermesDAO.recordTerminal(streamID: sid, terminal: str)
            currentStreamID = nil
        }
        switch terminal {
        case .success:
            HapticManager.play(.success)
        case .cancelled:
            HapticManager.play(.soft)
        case .error:
            HapticManager.play(.error)
        }
        Task { await refreshHistory() }
    }
}
