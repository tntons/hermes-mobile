//
//  HermesStore.swift
//  Hermes
//
//  SwiftData cache: finalized Messages per session + StreamCursor (last event id per run).
//  Offline-first read-through so the user can scroll history when the network is flaky.
//

import Foundation
import SwiftData

// MARK: - Persisted models

@Model
public final class PersistedSession {
    @Attribute(.unique) public var sessionID: String
    public var title: String
    public var workspace: String?
    public var model: String?
    public var modelProvider: String?
    public var messageCount: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var lastMessageAt: Date?
    public var pinned: Bool
    public var archived: Bool
    public var profile: String?
    public var inputTokens: Int
    public var outputTokens: Int
    public var estimatedCost: Double?
    public var activeStreamID: String?

    public init(from s: Session) {
        self.sessionID = s.session_id
        self.title = s.title
        self.workspace = s.workspace
        self.model = s.model
        self.modelProvider = s.model_provider
        self.messageCount = s.message_count
        self.createdAt = Date(timeIntervalSince1970: s.created_at)
        self.updatedAt = Date(timeIntervalSince1970: s.updated_at)
        self.lastMessageAt = s.last_message_at.map { Date(timeIntervalSince1970: $0) }
        self.pinned = s.pinned
        self.archived = s.archived
        self.profile = s.profile
        self.inputTokens = s.input_tokens
        self.outputTokens = s.output_tokens
        self.estimatedCost = s.estimated_cost
        self.activeStreamID = s.active_stream_id
    }

    public func apply(_ s: Session) {
        self.title = s.title
        self.workspace = s.workspace
        self.model = s.model
        self.modelProvider = s.model_provider
        self.messageCount = s.message_count
        self.updatedAt = Date(timeIntervalSince1970: s.updated_at)
        self.lastMessageAt = s.last_message_at.map { Date(timeIntervalSince1970: $0) }
        self.pinned = s.pinned
        self.archived = s.archived
        self.profile = s.profile
        self.inputTokens = s.input_tokens
        self.outputTokens = s.output_tokens
        self.estimatedCost = s.estimated_cost
        self.activeStreamID = s.active_stream_id
    }

    public func toModel() -> Session {
        Session(
            session_id: sessionID,
            title: title,
            workspace: workspace,
            model: model,
            model_provider: modelProvider,
            message_count: messageCount,
            created_at: createdAt.timeIntervalSince1970,
            updated_at: updatedAt.timeIntervalSince1970,
            last_message_at: lastMessageAt?.timeIntervalSince1970,
            pinned: pinned,
            archived: archived,
            profile: profile,
            input_tokens: inputTokens,
            output_tokens: outputTokens,
            estimated_cost: estimatedCost,
            is_streaming: activeStreamID != nil,
            has_pending_user_message: nil,
            active_stream_id: activeStreamID
        )
    }
}

@Model
public final class PersistedMessage {
    @Attribute(.unique) public var id: String
    public var sessionID: String
    public var role: String
    public var text: String
    public var reasoning: String?
    public var timestamp: Date
    public var isFinal: Bool

    public init(id: String, sessionID: String, role: String, text: String, reasoning: String?, timestamp: Date, isFinal: Bool) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.text = text
        self.reasoning = reasoning
        self.timestamp = timestamp
        self.isFinal = isFinal
    }
}

/// Tracks an in-flight turn for resume after background/disconnect.
@Model
public final class StreamCursor {
    @Attribute(.unique) public var streamID: String
    public var sessionID: String
    public var lastEventID: String?
    public var terminal: String?    // "success" | "cancelled" | "error:..."
    public var createdAt: Date
    public var updatedAt: Date

    public init(streamID: String, sessionID: String, lastEventID: String? = nil, terminal: String? = nil) {
        self.streamID = streamID
        self.sessionID = sessionID
        self.lastEventID = lastEventID
        self.terminal = terminal
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
    }
}

// MARK: - Container

public enum HermesStore {
    public static let shared: ModelContainer = {
        let schema = Schema([
            PersistedSession.self,
            PersistedMessage.self,
            StreamCursor.self,
        ])
        let config = ModelConfiguration("Hermes", schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // If the model is incompatible with an old on-disk store, drop & retry.
            // SwiftData migration is more work than necessary for v1; nuke & restart.
            do {
                try FileManager.default.removeItem(
                    at: config.url
                )
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                return try ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration("Hermes", isStoredInMemoryOnly: true)
                )
            }
        }
    }()
}

// MARK: - CRUD

@MainActor
public enum HermesDAO {
    public static let context = ModelContext(HermesStore.shared)

    // Sessions

    public static func upsert(_ sessions: [Session]) {
        for s in sessions {
            let sid = s.session_id
            let descriptor = FetchDescriptor<PersistedSession>(
                predicate: #Predicate { $0.sessionID == sid }
            )
            do {
                if let existing = try context.fetch(descriptor).first {
                    existing.apply(s)
                } else {
                    context.insert(PersistedSession(from: s))
                }
            } catch {
                // swiftdata predicate may fail on the first launch (no sessions yet)
                context.insert(PersistedSession(from: s))
            }
        }
        try? context.save()
    }

    public static func cachedSessions() -> [Session] {
        let descriptor = FetchDescriptor<PersistedSession>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map { $0.toModel() }
    }

    public static func delete(sessionID: String) {
        let sid = sessionID
        let descriptor = FetchDescriptor<PersistedSession>(
            predicate: #Predicate { $0.sessionID == sid }
        )
        if let row = try? context.fetch(descriptor).first {
            context.delete(row)
        }
        try? context.save()
    }

    // Messages

    public static func upsertMessages(sessionID: String, messages: [Message]) {
        let sid = sessionID
        let descriptor = FetchDescriptor<PersistedMessage>(
            predicate: #Predicate { $0.sessionID == sid }
        )
        if let existing = try? context.fetch(descriptor) {
            for row in existing { context.delete(row) }
        }
        for m in messages {
            let idStr = "\(sid)-\(m.timestamp)-\(m.role.rawValue)-\(m.textRepresentation.hashValue)"
            context.insert(PersistedMessage(
                id: idStr,
                sessionID: sid,
                role: m.role.rawValue,
                text: m.textRepresentation,
                reasoning: m.reasoning,
                timestamp: Date(timeIntervalSince1970: m.timestamp),
                isFinal: m.isFinal
            ))
        }
        try? context.save()
    }

    public static func appendMessage(_ message: ChatMessage, sessionID: String) {
        let idStr = "\(sessionID)-\(message.timestamp.timeIntervalSince1970)-\(message.role.rawValue)-\(message.id.uuidString)"
        context.insert(PersistedMessage(
            id: idStr,
            sessionID: sessionID,
            role: message.role.rawValue,
            text: message.text,
            reasoning: message.reasoning.isEmpty ? nil : message.reasoning,
            timestamp: message.timestamp,
            isFinal: message.isFinal
        ))
        try? context.save()
    }

    public static func cachedMessages(sessionID: String) -> [PersistedMessage] {
        let sid = sessionID
        let descriptor = FetchDescriptor<PersistedMessage>(
            predicate: #Predicate { $0.sessionID == sid },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // Stream cursors

    public static func recordCursor(streamID: String, sessionID: String, lastEventID: String? = nil) {
        let descriptor = FetchDescriptor<StreamCursor>(
            predicate: #Predicate { $0.streamID == streamID }
        )
        if let row = try? context.fetch(descriptor).first {
            if let eid = lastEventID { row.lastEventID = eid }
            row.updatedAt = .now
        } else {
            context.insert(StreamCursor(streamID: streamID, sessionID: sessionID, lastEventID: lastEventID))
        }
        try? context.save()
    }

    public static func recordTerminal(streamID: String, terminal: String) {
        let descriptor = FetchDescriptor<StreamCursor>(
            predicate: #Predicate { $0.streamID == streamID }
        )
        if let row = try? context.fetch(descriptor).first {
            row.terminal = terminal
            row.updatedAt = .now
        }
        try? context.save()
    }

    public static func openCursors() -> [StreamCursor] {
        let descriptor = FetchDescriptor<StreamCursor>(
            predicate: #Predicate { $0.terminal == nil || $0.terminal == "" }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    public static func cursor(streamID: String) -> StreamCursor? {
        let sid = streamID
        let descriptor = FetchDescriptor<StreamCursor>(
            predicate: #Predicate { $0.streamID == sid }
        )
        return (try? context.fetch(descriptor))?.first
    }
}
