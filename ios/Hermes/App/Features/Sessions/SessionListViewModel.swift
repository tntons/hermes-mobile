//
//  SessionListViewModel.swift
//  Hermes
//

import Foundation
import Observation

@Observable
@MainActor
public final class SessionListViewModel {
    public var sessions: [Session] = []
    public var isLoading: Bool = false
    public var errorMessage: String?

    private var client: HermesClient?
    private var isMock = false

    public init() {}

    public func bootstrap(config: APIConfig) async {
        if config.isMock {
            isMock = true
            sessions = MockData.sessions
            return
        }
        guard config.isConfigured,
              let url = config.gatewayURL,
              let token = config.bearerToken
        else { return }
        let c = HermesClient(config: .init(gatewayURL: url, bearerToken: token))
        self.client = c
        sessions = HermesDAO.cachedSessions()
        await refresh()
    }

    public func refresh() async {
        guard let client = client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await client.fetchSessions()
            self.sessions = list
            self.errorMessage = nil
            HermesDAO.upsert(list)
        } catch APIError.unauthorized {
            self.errorMessage = "Bearer token rejected. Open Settings to update."
        } catch APIError.offline {
            self.errorMessage = "Offline — showing cached sessions."
        } catch {
            self.errorMessage = "Could not load sessions. Pull to retry."
        }
    }

    public func newSession(model: String? = nil) async -> Session? {
        if isMock {
            let now = Date.now.timeIntervalSince1970
            let session = Session(
                session_id: UUID().uuidString,
                title: "New demo session",
                workspace: "~/demo-workspace",
                model: model ?? "demo-model",
                model_provider: "Mock",
                created_at: now,
                updated_at: now,
                last_message_at: now,
                profile: "demo"
            )
            sessions.insert(session, at: 0)
            return session
        }
        guard let client = client else { return nil }
        let profile = KeychainStore.shared.profile
        do {
            let req = NewSessionRequest(model: model, profile: profile)
            let s = try await client.newSession(req)
            await refresh()
            return s
        } catch {
            errorMessage = "Could not create session: \(error.localizedDescription)"
            return nil
        }
    }

    public func rename(_ sessionID: String, to title: String) async {
        if isMock {
            updateSession(sessionID) { $0.title = title; $0.updated_at = Date.now.timeIntervalSince1970 }
            return
        }
        guard let client = client else { return }
        do {
            try await client.renameSession(sessionID: sessionID, to: title)
            if let idx = sessions.firstIndex(where: { $0.session_id == sessionID }) {
                var s = sessions[idx]
                s.title = title
                sessions[idx] = s
            }
            HermesDAO.upsert(sessions)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func togglePin(_ session: Session) async {
        if isMock {
            updateSession(session.session_id) { $0.pinned.toggle() }
            return
        }
        guard let client = client else { return }
        do {
            try await client.setSessionPinned(sessionID: session.session_id, pinned: !session.pinned)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func toggleArchive(_ session: Session) async {
        if isMock {
            updateSession(session.session_id) { $0.archived.toggle() }
            return
        }
        guard let client = client else { return }
        do {
            try await client.setSessionArchived(sessionID: session.session_id, archived: !session.archived)
            sessions.removeAll { $0.session_id == session.session_id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func delete(_ session: Session) async {
        if isMock {
            sessions.removeAll { $0.session_id == session.session_id }
            return
        }
        guard let client = client else { return }
        do {
            try await client.deleteSession(sessionID: session.session_id)
            sessions.removeAll { $0.session_id == session.session_id }
            HermesDAO.delete(sessionID: session.session_id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Grouping

    public struct Group: Identifiable {
        public let id: String           // "Today" | "Yesterday" | "Earlier"
        public var title: String { id }
        public var items: [Session]
    }

    public var grouped: [Group] {
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let yesterdayStart = cal.date(byAdding: .day, value: -1, to: todayStart)!
        return HermesListGroup.group(sessions, today: todayStart, yesterday: yesterdayStart)
    }

    private func updateSession(_ sessionID: String, _ update: (inout Session) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.session_id == sessionID }) else { return }
        update(&sessions[index])
    }
}

enum MockData {
    static var sessions: [Session] {
        let now = Date.now.timeIntervalSince1970
        return [
            Session(
                session_id: "demo-session-1",
                title: "Welcome to Hermes",
                workspace: "~/demo-workspace",
                model: "demo-model",
                model_provider: "Mock",
                message_count: 2,
                created_at: now - 3600,
                updated_at: now - 180,
                last_message_at: now - 180,
                profile: "demo"
            ),
            Session(
                session_id: "demo-session-2",
                title: "Plan a weekend project",
                workspace: "~/demo-workspace",
                model: "demo-model",
                model_provider: "Mock",
                message_count: 4,
                created_at: now - 86_400,
                updated_at: now - 3_600,
                last_message_at: now - 3_600,
                profile: "demo"
            )
        ]
    }

    static func messages(for sessionID: String) -> [ChatMessage] {
        switch sessionID {
        case "demo-session-2":
            return [
                .user("Help me plan a small weekend project."),
                ChatMessage(
                    role: .assistant,
                    text: "Absolutely. Start with the outcome, break it into three small tasks, and leave a little time for testing.",
                    terminal: .success,
                    isFinal: true
                )
            ]
        default:
            return [
                .user("What is Hermes?"),
                ChatMessage(
                    role: .assistant,
                    text: "Hermes is your personal coding assistant. This demo account is running entirely from local sample data.",
                    terminal: .success,
                    isFinal: true
                )
            ]
        }
    }
}

enum HermesListGroup {
    static func group(_ sessions: [Session], today: Date, yesterday: Date) -> [SessionListViewModel.Group] {
        var pinned: [Session] = []
        var todayRow: [Session] = []
        var yesterdayRow: [Session] = []
        var earlierRow: [Session] = []

        for s in sessions.sorted(by: { ($0.last_message_at ?? 0) > ($1.last_message_at ?? 0) }) {
            if s.archived { continue }
            if s.pinned { pinned.append(s); continue }
            let ts = Date(timeIntervalSince1970: s.last_message_at ?? s.updated_at)
            if ts >= today { todayRow.append(s) }
            else if ts >= yesterday { yesterdayRow.append(s) }
            else { earlierRow.append(s) }
        }

        var result: [SessionListViewModel.Group] = []
        if !pinned.isEmpty { result.append(.init(id: "Pinned", items: pinned)) }
        if !todayRow.isEmpty { result.append(.init(id: "Today", items: todayRow)) }
        if !yesterdayRow.isEmpty { result.append(.init(id: "Yesterday", items: yesterdayRow)) }
        if !earlierRow.isEmpty { result.append(.init(id: "Earlier", items: earlierRow)) }
        return result
    }
}
