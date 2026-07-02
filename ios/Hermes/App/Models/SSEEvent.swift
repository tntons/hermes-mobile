//
//  SSEEvent.swift
//  Hermes
//
//  Parsed SSE event types from /api/chat/stream.
//  See IMPLEMENTATION_PLAN.md §3.4.
//

import Foundation

// MARK: - Event surface

public enum SSEEvent: Sendable {
    case token(text: String)
    case reasoning(text: String)
    case interimAssistant(text: String, alreadyStreamed: Bool)
    case tool(ToolEvent)
    case toolComplete(ToolCompleteEvent)
    case approval(ApprovalEvent)
    case clarify(ClarifyEvent)
    case metering(MeteringEvent)
    case contextStatus(AnyCodable)
    case compressing
    case compressed(CompressedEvent)
    case warning(WarningEvent)
    case todoState(AnyCodable)
    case stateSaved(AnyCodable)
    case goal(GoalEvent)
    case goalContinue(GoalEvent)
    case done(DoneEvent)            // TERMINAL success
    case streamEnd                  // TERMINAL always after done
    case cancel(CancelEvent)        // TERMINAL
    case appError(AppErrorEvent)    // TERMINAL
    case keepAlive                  // comment heartbeat

    public struct ToolEvent: Sendable {
        public let name: String
        public let preview: String?
        public let args: AnyCodable?
    }

    public struct ToolCompleteEvent: Sendable {
        public let name: String
        public let preview: String?
        public let args: AnyCodable?
        public let duration: Double?
        public let is_error: Bool?
    }

    public struct ApprovalEvent: Sendable {
        public let command: String
        public let description: String
        public let pattern_key: String?
        public let pattern_keys: [String]?
        public let choices: [String]
        public let allow_permanent: Bool?
        public let run_id: String?
        public let approval_id: String?
    }

    public struct ClarifyEvent: Sendable {
        public let question: String
        public let choices_offered: [String]?
        public let timeout_seconds: Int?
    }

    public struct CompressedEvent: Sendable {
        public let old_session_id: String
        public let new_session_id: String?
        public let continuation_session_id: String?
    }

    public struct WarningEvent: Sendable {
        public let type: String?
        public let message: String
    }

    public struct GoalEvent: Sendable {
        public let state: String?
        public let message: String?
        public let message_key: String?
    }

    public struct DoneEvent: Sendable {
        public let session: SessionDetailResponse?
        public let usage: Usage?
        public let terminal_state: String?
        public let terminal_reason: String?
    }

    public struct CancelEvent: Sendable {
        public let message: String?
        public let type: String?
        public let status: String?
        public let session_id: String?
    }

    public struct AppErrorEvent: Sendable {
        public let label: String?
        public let type: String
        public let message: String
        public let hint: String?
        public let details: String?
        public let session_id: String?
        public let terminal_state: String?
        public let terminal_reason: String?
    }

    public struct MeteringEvent: Sendable {
        public let usage: AnyCodable?
        public let estimated: Bool?
    }

    public struct Usage: Codable, Sendable {
        public let input_tokens: Int?
        public let output_tokens: Int?
        public let estimated_cost: Double?
    }
}

public enum TerminalState: Equatable, Sendable {
    case success, cancelled, error(String)

    public var isSuccess: Bool { if case .success = self { return true } else { return false } }
    public var isCancelled: Bool { if case .cancelled = self { return true } else { return false } }
}

// MARK: - Parser

public enum SSEParser {
    /// Parse a single SSE frame (`event:` / `data:` / `id:` lines + blank) into
    /// a typed `SSEEvent`. Returns `.keepAlive` for comment-only frames.
    public static func parse(eventName: String?, data: String, id: String?) -> SSEEvent? {
        guard let name = eventName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else {
            return .keepAlive
        }

        let anyData = AnyCodable(parseJSON(data) ?? NSNull())
        switch name {
        case "token":
            let text = (try? anyData.value as? String) ?? extractText(anyData.value) ?? ""
            return .token(text: text)
        case "reasoning":
            let text = (try? anyData.value as? String) ?? extractText(anyData.value) ?? ""
            return .reasoning(text: text)
        case "interim_assistant":
            let dict = (anyData.value as? [String: Any]) ?? [:]
            let text = (dict["text"] as? String) ?? ""
            let already = (dict["already_streamed"] as? Bool) ?? false
            return .interimAssistant(text: text, alreadyStreamed: already)
        case "tool":
            let dict = (anyData.value as? [String: Any]) ?? [:]
            let tool = SSEEvent.ToolEvent(
                name: (dict["name"] as? String) ?? "tool",
                preview: dict["preview"] as? String,
                args: AnyCodable(dict["args"] ?? NSNull())
            )
            return .tool(tool)
        case "tool_complete":
            let dict = (anyData.value as? [String: Any]) ?? [:]
            let tool = SSEEvent.ToolCompleteEvent(
                name: (dict["name"] as? String) ?? "tool",
                preview: dict["preview"] as? String,
                args: AnyCodable(dict["args"] ?? NSNull()),
                duration: (dict["duration"] as? Double) ?? (dict["duration"] as? NSNumber)?.doubleValue,
                is_error: dict["is_error"] as? Bool
            )
            return .toolComplete(tool)
        case "approval":
            let dict = (anyData.value as? [String: Any]) ?? [:]
            let choices = (dict["choices"] as? [String]) ?? ["once", "session", "always", "deny"]
            let ev = SSEEvent.ApprovalEvent(
                command: (dict["command"] as? String) ?? "",
                description: (dict["description"] as? String) ?? "",
                pattern_key: dict["pattern_key"] as? String,
                pattern_keys: dict["pattern_keys"] as? [String],
                choices: choices,
                allow_permanent: dict["allow_permanent"] as? Bool,
                run_id: dict["run_id"] as? String,
                approval_id: dict["approval_id"] as? String
            )
            return .approval(ev)
        case "clarify":
            let dict = (anyData.value as? [String: Any]) ?? [:]
            let ev = SSEEvent.ClarifyEvent(
                question: (dict["question"] as? String) ?? "",
                choices_offered: dict["choices_offered"] as? [String],
                timeout_seconds: (dict["timeout_seconds"] as? Int)
            )
            return .clarify(ev)
        case "metering":
            let dict = (anyData.value as? [String: Any]) ?? [:]
            return .metering(.init(usage: AnyCodable(dict["usage"] ?? NSNull()), estimated: dict["estimated"] as? Bool))
        case "context_status":
            return .contextStatus(anyData)
        case "compressing":
            return .compressing
        case "compressed":
            let dict = (anyData.value as? [String: Any]) ?? [:]
            let ev = SSEEvent.CompressedEvent(
                old_session_id: (dict["old_session_id"] as? String) ?? "",
                new_session_id: dict["new_session_id"] as? String,
                continuation_session_id: dict["continuation_session_id"] as? String
            )
            return .compressed(ev)
        case "warning":
            let dict = (anyData.value as? [String: Any]) ?? [:]
            let ev = SSEEvent.WarningEvent(
                type: dict["type"] as? String,
                message: (dict["message"] as? String) ?? ""
            )
            return .warning(ev)
        case "todo_state":
            return .todoState(anyData)
        case "state_saved":
            return .stateSaved(anyData)
        case "goal":
            let dict = (anyData.value as? [String: Any]) ?? [:]
            return .goal(.init(state: dict["state"] as? String, message: dict["message"] as? String, message_key: dict["message_key"] as? String))
        case "goal_continue":
            let dict = (anyData.value as? [String: Any]) ?? [:]
            return .goalContinue(.init(state: dict["state"] as? String, message: dict["message"] as? String, message_key: dict["message_key"] as? String))
        case "done":
            let dict = (anyData.value as? [String: Any]) ?? [:]
            let usage: SSEEvent.Usage? = {
                guard let u = dict["usage"] as? [String: Any] else { return nil }
                return SSEEvent.Usage(
                    input_tokens: u["input_tokens"] as? Int,
                    output_tokens: u["output_tokens"] as? Int,
                    estimated_cost: (u["estimated_cost"] as? Double) ?? (u["estimated_cost"] as? NSNumber)?.doubleValue
                )
            }()
            let session: SessionDetailResponse? = {
                guard let s = dict["session"] as? [String: Any] else { return nil }
                guard let data = try? JSONSerialization.data(withJSONObject: s, options: []) else { return nil }
                return try? JSONDecoder().decode(SessionDetailResponse.self, from: data)
            }()
            let ev = SSEEvent.DoneEvent(
                session: session,
                usage: usage,
                terminal_state: dict["terminal_state"] as? String,
                terminal_reason: dict["terminal_reason"] as? String
            )
            return .done(ev)
        case "stream_end":
            return .streamEnd
        case "cancel":
            let dict = (anyData.value as? [String: Any]) ?? [:]
            let ev = SSEEvent.CancelEvent(
                message: dict["message"] as? String,
                type: dict["type"] as? String,
                status: dict["status"] as? String,
                session_id: dict["session_id"] as? String
            )
            return .cancel(ev)
        case "apperror":
            let dict = (anyData.value as? [String: Any]) ?? [:]
            let ev = SSEEvent.AppErrorEvent(
                label: dict["label"] as? String,
                type: (dict["type"] as? String) ?? "error",
                message: (dict["message"] as? String) ?? "Stream error",
                hint: dict["hint"] as? String,
                details: dict["details"] as? String,
                session_id: dict["session_id"] as? String,
                terminal_state: dict["terminal_state"] as? String,
                terminal_reason: dict["terminal_reason"] as? String
            )
            return .appError(ev)
        default:
            return nil    // unknown event — ignore
        }
    }

    /// Map a parsed `SSEEvent` to its `TerminalState` (or `nil` if non-terminal).
    public static func terminalState(of event: SSEEvent) -> TerminalState? {
        switch event {
        case .done: return .success
        case .cancel: return .cancelled
        case .appError(let e): return .error(e.message)
        case .streamEnd: return .success    // treat as success close
        default: return nil
        }
    }
}

// MARK: - Tiny JSON helpers

private func parseJSON(_ s: String) -> Any? {
    guard let data = s.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
}

private func extractText(_ v: Any) -> String? {
    if let s = v as? String { return s }
    if let dict = v as? [String: Any] {
        if let s = dict["text"] as? String { return s }
    }
    if let arr = v as? [Any] {
        let joined = arr.compactMap { extractText($0) }.joined()
        return joined
    }
    return nil
}
