//
//  JarvisModels.swift
//  JARVIS
//
//  Codable types matching the hermes-webui API contract.
//  These are the SINGLE SOURCE OF TRUTH for the transport layer.
//

import Foundation

// MARK: - Session

public struct Session: Codable, Identifiable, Hashable, Sendable {
    public var id: String { session_id }

    public let session_id: String
    public var title: String
    public var workspace: String?
    public var model: String?
    public var model_provider: String?
    public var message_count: Int
    public var created_at: Double
    public var updated_at: Double
    public var last_message_at: Double?
    public var pinned: Bool
    public var archived: Bool
    public var project_id: String?
    public var profile: String?
    public var personality: String?
    public var input_tokens: Int
    public var output_tokens: Int
    public var estimated_cost: Double?
    public var is_streaming: Bool?
    public var has_pending_user_message: Bool?
    public var active_stream_id: String?

    // Detail-only fields: present in `/api/session?...&messages=1`,
    // absent in `/api/sessions`. Decoded defensively (nil if missing).
    public var messages: [Message]?
    public var tool_calls: [ToolCallRef]?
    public var end_reason: String?
    public var actual_message_count: Int?

    private enum CodingKeys: String, CodingKey {
        case session_id, title, workspace, model, model_provider, message_count
        case created_at, updated_at, last_message_at, pinned, archived, project_id, profile, personality
        case input_tokens, output_tokens, estimated_cost
        case is_streaming, has_pending_user_message, active_stream_id
        case messages, tool_calls, end_reason, actual_message_count
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // All webui fields are tolerant — defensive decoding for forward compat.
        self.session_id = try c.decode(String.self, forKey: .session_id)
        self.title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled"
        self.workspace = try? c.decodeIfPresent(String.self, forKey: .workspace)
        self.model = try? c.decodeIfPresent(String.self, forKey: .model)
        self.model_provider = try? c.decodeIfPresent(String.self, forKey: .model_provider)
        self.message_count = (try? c.decode(Int.self, forKey: .message_count)) ?? 0
        self.created_at = (try? c.decode(Double.self, forKey: .created_at)) ?? 0
        self.updated_at = (try? c.decode(Double.self, forKey: .updated_at)) ?? 0
        self.last_message_at = try? c.decodeIfPresent(Double.self, forKey: .last_message_at)
        self.pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? false
        self.archived = (try? c.decode(Bool.self, forKey: .archived)) ?? false
        self.project_id = try? c.decodeIfPresent(String.self, forKey: .project_id)
        self.profile = try? c.decodeIfPresent(String.self, forKey: .profile)
        self.personality = try? c.decodeIfPresent(String.self, forKey: .personality)
        self.input_tokens = (try? c.decode(Int.self, forKey: .input_tokens)) ?? 0
        self.output_tokens = (try? c.decode(Int.self, forKey: .output_tokens)) ?? 0
        self.estimated_cost = try? c.decodeIfPresent(Double.self, forKey: .estimated_cost)
        self.is_streaming = try? c.decodeIfPresent(Bool.self, forKey: .is_streaming)
        self.has_pending_user_message = try? c.decodeIfPresent(Bool.self, forKey: .has_pending_user_message)
        self.active_stream_id = try? c.decodeIfPresent(String.self, forKey: .active_stream_id)
        // Detail-only fields (nil in /api/sessions list response):
        self.messages = try? c.decodeIfPresent([Message].self, forKey: .messages)
        self.tool_calls = try? c.decodeIfPresent([ToolCallRef].self, forKey: .tool_calls)
        self.end_reason = try? c.decodeIfPresent(String.self, forKey: .end_reason)
        self.actual_message_count = try? c.decodeIfPresent(Int.self, forKey: .actual_message_count)
    }

    public init(
        session_id: String,
        title: String,
        workspace: String? = nil,
        model: String? = nil,
        model_provider: String? = nil,
        message_count: Int = 0,
        created_at: Double = Date.now.timeIntervalSince1970,
        updated_at: Double = Date.now.timeIntervalSince1970,
        last_message_at: Double? = nil,
        pinned: Bool = false,
        archived: Bool = false,
        project_id: String? = nil,
        profile: String? = nil,
        personality: String? = nil,
        input_tokens: Int = 0,
        output_tokens: Int = 0,
        estimated_cost: Double? = nil,
        is_streaming: Bool? = nil,
        has_pending_user_message: Bool? = nil,
        active_stream_id: String? = nil,
        messages: [Message]? = nil,
        tool_calls: [ToolCallRef]? = nil,
        end_reason: String? = nil,
        actual_message_count: Int? = nil
    ) {
        self.session_id = session_id
        self.title = title
        self.workspace = workspace
        self.model = model
        self.model_provider = model_provider
        self.message_count = message_count
        self.created_at = created_at
        self.updated_at = updated_at
        self.last_message_at = last_message_at
        self.pinned = pinned
        self.archived = archived
        self.project_id = project_id
        self.profile = profile
        self.personality = personality
        self.input_tokens = input_tokens
        self.output_tokens = output_tokens
        self.estimated_cost = estimated_cost
        self.is_streaming = is_streaming
        self.has_pending_user_message = has_pending_user_message
        self.active_stream_id = active_stream_id
        self.messages = messages
        self.tool_calls = tool_calls
        self.end_reason = end_reason
        self.actual_message_count = actual_message_count
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(session_id, forKey: .session_id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(workspace, forKey: .workspace)
        try c.encodeIfPresent(model, forKey: .model)
        try c.encodeIfPresent(model_provider, forKey: .model_provider)
        try c.encode(message_count, forKey: .message_count)
        try c.encode(created_at, forKey: .created_at)
        try c.encode(updated_at, forKey: .updated_at)
        try c.encodeIfPresent(last_message_at, forKey: .last_message_at)
        try c.encode(pinned, forKey: .pinned)
        try c.encode(archived, forKey: .archived)
        try c.encodeIfPresent(project_id, forKey: .project_id)
        try c.encodeIfPresent(profile, forKey: .profile)
        try c.encodeIfPresent(personality, forKey: .personality)
        try c.encode(input_tokens, forKey: .input_tokens)
        try c.encode(output_tokens, forKey: .output_tokens)
        try c.encodeIfPresent(estimated_cost, forKey: .estimated_cost)
        try c.encodeIfPresent(is_streaming, forKey: .is_streaming)
        try c.encodeIfPresent(has_pending_user_message, forKey: .has_pending_user_message)
        try c.encodeIfPresent(active_stream_id, forKey: .active_stream_id)
        try c.encodeIfPresent(messages, forKey: .messages)
        try c.encodeIfPresent(tool_calls, forKey: .tool_calls)
        try c.encodeIfPresent(end_reason, forKey: .end_reason)
        try c.encodeIfPresent(actual_message_count, forKey: .actual_message_count)
    }

    public var displayTimestamp: Date {
        Date(timeIntervalSince1970: last_message_at ?? updated_at)
    }
}

public struct SessionListResponse: Codable, Sendable {
    public let sessions: [Session]
    public let active_profile: String?
    public let server_time: Double?
    public let server_tz: String?
    public let archived_count: Int?
}

public struct SessionDetailResponse: Codable, Sendable {
    // hermes-webui nests `messages`, `tool_calls`, etc. INSIDE `session`,
    // not at the top level as the IMPLEMENTATION_PLAN §3.2 originally
    // documented. Expose them as computed accessors so callers can keep
    // using `detail.messages` / `detail.tool_calls` unchanged.
    public let session: Session

    public var messages: [Message] { session.messages ?? [] }
    public var tool_calls: [ToolCallRef]? { session.tool_calls }
}

public struct TodoState: Codable, Hashable, Sendable {
    public let items: [AnyCodable]?
}

// MARK: - Message

public struct Message: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Hashable, Sendable {
        case user, assistant, system, tool
    }

    public let role: Role
    public let content: MessageContent
    public let timestamp: Double
    public let reasoning: String?
    public let attachments: [Attachment]?
    public let tool_calls: [ToolCall]?
    public let tool_call_id: String?
    public let _partial: Bool?
    public let _error: Bool?
    // webui extras — surfaced for SSE handler / tool display:
    public let tool_name: String?
    public let name: String?
    public let reasoning_content: String?
    public let reasoning_details: AnyCodable?

    private enum CodingKeys: String, CodingKey {
        case role, content, timestamp, reasoning, attachments
        case tool_calls, tool_call_id, _partial, _error
        case tool_name, name, reasoning_content, reasoning_details
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // All fields defensive — a single bad message must not poison the
        // whole `[Message]` array. This mirrors Session's decoder pattern
        // and matches the actual webui contract: tool_calls use a nested
        // shape (`function.name` + `function.arguments`) different from
        // our local `ToolCall`, so we capture what we can and drop the rest.
        self.role = (try? c.decode(Role.self, forKey: .role)) ?? .user
        let decodedContent: MessageContent = (try? c.decodeIfPresent(MessageContent.self, forKey: .content)) ?? .text("")
        self.content = decodedContent
        self.timestamp = (try? c.decode(Double.self, forKey: .timestamp)) ?? 0
        self.reasoning = try? c.decodeIfPresent(String.self, forKey: .reasoning)
        self.attachments = try? c.decodeIfPresent([Attachment].self, forKey: .attachments)
        // webui's tool_calls shape: {id, type, function: {name, arguments}} — not compatible
        // with our local ToolCall. Capture raw JSON so ConversationViewModel
        // can still display a name + preview, then drop the typed field.
        self.tool_calls = try? c.decodeIfPresent([ToolCall].self, forKey: .tool_calls)
        self.tool_call_id = try? c.decodeIfPresent(String.self, forKey: .tool_call_id)
        self._partial = try? c.decodeIfPresent(Bool.self, forKey: ._partial)
        self._error = try? c.decodeIfPresent(Bool.self, forKey: ._error)
        self.tool_name = try? c.decodeIfPresent(String.self, forKey: .tool_name)
        self.name = try? c.decodeIfPresent(String.self, forKey: .name)
        self.reasoning_content = try? c.decodeIfPresent(String.self, forKey: .reasoning_content)
        self.reasoning_details = try? c.decodeIfPresent(AnyCodable.self, forKey: .reasoning_details)
    }

    public init(
        role: Role,
        content: MessageContent,
        timestamp: Double,
        reasoning: String? = nil,
        attachments: [Attachment]? = nil,
        tool_calls: [ToolCall]? = nil,
        tool_call_id: String? = nil,
        _partial: Bool? = nil,
        _error: Bool? = nil,
        tool_name: String? = nil,
        name: String? = nil,
        reasoning_content: String? = nil,
        reasoning_details: AnyCodable? = nil
    ) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.reasoning = reasoning
        self.attachments = attachments
        self.tool_calls = tool_calls
        self.tool_call_id = tool_call_id
        self._partial = _partial
        self._error = _error
        self.tool_name = tool_name
        self.name = name
        self.reasoning_content = reasoning_content
        self.reasoning_details = reasoning_details
    }

    public var isFinal: Bool { _partial != true && _error != true }

    public var textRepresentation: String {
        switch content {
        case .text(let s): return s
        case .blocks(let blocks):
            return blocks.map { $0.text ?? "" }.joined()
        }
    }
}

public enum MessageContent: Codable, Hashable, Sendable {
    case text(String)
    case blocks([ContentBlock])

    public struct ContentBlock: Codable, Hashable, Sendable {
        public let type: String
        public let text: String?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .text(s)
        } else if let blocks = try? c.decode([ContentBlock].self) {
            self = .blocks(blocks)
        } else {
            self = .text("")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let s): try c.encode(s)
        case .blocks(let b): try c.encode(b)
        }
    }
}

public struct Attachment: Codable, Hashable, Sendable {
    public let name: String
    public let path: String?
    public let mime: String?
    public let size: Int?
    public let is_image: Bool?
}

// MARK: - Tool calls

public struct ToolCall: Codable, Hashable, Sendable {
    public let name: String
    public let args: AnyCodable?
    public let result: AnyCodable?
    public let preview: String?
    public let duration: Double?
    public let is_error: Bool?

    public init(
        name: String,
        args: AnyCodable? = nil,
        result: AnyCodable? = nil,
        preview: String? = nil,
        duration: Double? = nil,
        is_error: Bool? = nil
    ) {
        self.name = name
        self.args = args
        self.result = result
        self.preview = preview
        self.duration = duration
        self.is_error = is_error
    }

    public var id: String { "\(name)-\((preview ?? "").hashValue)" }
}

public struct ToolCallRef: Codable, Hashable, Sendable {
    public let name: String
    public let args: AnyCodable?
    public let result: AnyCodable?
    public let preview: String?
}

// MARK: - Chat start

public struct ChatStartResponse: Codable, Sendable {
    public let stream_id: String
    public let session_id: String
    public let turn_id: String?
    public let effective_model: String?
    public let error: String?
}

// MARK: - Secretary approvals

public enum ApprovalStatus: String, Codable, Hashable, Sendable {
    case pending, approved, denied, expired, consumed
}

public struct ApprovalRecord: Codable, Identifiable, Sendable {
    public var id: String { approval_id }

    public let approval_id: String
    public let session_id: String
    public let stream_id: String?
    public let action_class: String
    public let tool_name: String
    public let command: String
    public let description: String
    public let choices: [String]
    public let source: String
    public let status: ApprovalStatus
    public let created_at: Double
    public let expires_at: Double
    public let decided_at: Double?
}

public struct ApprovalListResponse: Codable, Sendable {
    public let approvals: [ApprovalRecord]
}

public struct ApprovalDecisionRequest: Codable, Sendable {
    public let decision: String

    public init(decision: String) {
        self.decision = decision
    }
}

// MARK: - Request bodies

public struct NewSessionRequest: Codable, Sendable {
    public let workspace: String?
    public let model: String?
    public let model_provider: String?
    public let profile: String?

    public init(workspace: String? = nil, model: String? = nil, model_provider: String? = nil, profile: String? = nil) {
        self.workspace = workspace
        self.model = model
        self.model_provider = model_provider
        self.profile = profile
    }
}

public struct RenameSessionRequest: Codable, Sendable {
    public let session_id: String
    public let title: String
}

public struct DeleteSessionRequest: Codable, Sendable {
    public let session_id: String
    public let worktree_remove: Bool?
}

public struct PinSessionRequest: Codable, Sendable {
    public let session_id: String
    public let pinned: Bool
}

public struct ArchiveSessionRequest: Codable, Sendable {
    public let session_id: String
    public let archived: Bool
}

public struct ChatStartRequest: Codable, Sendable {
    public let session_id: String
    public let message: String
    public let attachments: [Attachment]?
    public let workspace: String?
    public let model: String?
    public let model_provider: String?
    public let profile: String?

    public init(
        session_id: String,
        message: String,
        attachments: [Attachment]? = nil,
        workspace: String? = nil,
        model: String? = nil,
        model_provider: String? = nil,
        profile: String? = nil
    ) {
        self.session_id = session_id
        self.message = message
        self.attachments = attachments
        self.workspace = workspace
        self.model = model
        self.model_provider = model_provider
        self.profile = profile
    }
}
