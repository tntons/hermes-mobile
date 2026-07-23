//
//  SessionListView.swift
//  JARVIS
//

import SwiftUI

private struct ConversationRoute: Hashable {
    let session: Session
    let initialMessage: String?
}

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(APIConfig.self) private var apiConfig
    @State private var viewModel = SessionListViewModel()
    @State private var path = NavigationPath()
    @State private var draft = ""
    @State private var isCreatingConversation = false
    @State private var presentSettings = false
    @State private var presentHistory = false
    @State private var streamingLockedSession: Session?
    @State private var showAttachmentNotice = false

    private let suggestedPrompts = [
        "Review a code snippet",
        "Help me debug an error",
        "Plan a coding task",
        "Explain a concept"
    ]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    if appState.reachability == .offline || viewModel.errorMessage != nil {
                        homeStatus
                            .padding(.bottom, JarvisTheme.Spacing.md)
                    }
                    promptSuggestions
                    homeComposer

                    if viewModel.isLoading && viewModel.sessions.isEmpty {
                        JarvisHistorySkeleton()
                            .padding(.top, JarvisTheme.Spacing.xl)
                    } else if viewModel.sessions.isEmpty {
                        JarvisEmptyState(
                            systemImage: viewModel.errorMessage == nil ? "bubble.left.and.bubble.right" : "wifi.exclamationmark",
                            title: viewModel.errorMessage == nil ? "No conversations yet" : "We couldn't load conversations",
                            message: viewModel.errorMessage == nil
                                ? "Start with the composer above and your recent work will appear here."
                                : "Check your connection, then try loading your conversations again.",
                            actionTitle: viewModel.errorMessage == nil ? nil : "Try again",
                            action: viewModel.errorMessage == nil ? nil : { Task { await viewModel.refresh() } }
                        )
                        .padding(.top, JarvisTheme.Spacing.xl)
                    } else if !viewModel.recentSessions.isEmpty {
                        recentConversations
                    }
                }
                .padding(.horizontal, JarvisTheme.Spacing.md)
                .padding(.bottom, JarvisTheme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .background(JarvisTheme.background.ignoresSafeArea())
            .refreshable { await viewModel.refresh() }
            .navigationTitle(JarvisBrand.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(JarvisTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        presentSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("All conversations")
                }
            }
            .alert("Attachments", isPresented: $showAttachmentNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Mobile file and photo uploads are not available yet. The attachment control is ready for a future update.")
            }
            .navigationDestination(for: ConversationRoute.self) { route in
                ConversationView(
                    sessionID: route.session.session_id,
                    title: route.session.title,
                    initialMessage: route.initialMessage
                )
                .environment(apiConfig)
            }
            .sheet(isPresented: $presentSettings) {
                SettingsView()
                    .environment(appState)
                    .environment(apiConfig)
            }
            .sheet(isPresented: $presentHistory) {
                SessionHistoryView(viewModel: viewModel)
                    .environment(appState)
                    .environment(apiConfig)
            }
            .alert(
                "Conversation is streaming",
                isPresented: Binding(
                    get: { streamingLockedSession != nil },
                    set: { if !$0 { streamingLockedSession = nil } }
                ),
                presenting: streamingLockedSession
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { session in
                Text("'\(session.title)' is actively streaming on another device. Wait for the current turn to finish, then try again.")
            }
            .task {
                await viewModel.bootstrap(config: apiConfig)
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "_debug.openFirstSession"),
                   let first = viewModel.sessions.first,
                   path.isEmpty {
                    UserDefaults.standard.set(false, forKey: "_debug.openFirstSession")
                    path.append(ConversationRoute(session: first, initialMessage: nil))
                }
                #endif
            }
        }
    }

    @ViewBuilder
    private var homeStatus: some View {
        if appState.reachability == .offline {
            JarvisStateBanner(
                title: "Offline mode",
                message: viewModel.sessions.isEmpty
                    ? "JARVIS cannot reach the gateway right now."
                    : "Showing your saved conversations until the connection returns.",
                systemImage: "wifi.slash",
                tone: .warning,
                actionTitle: "Retry",
                action: { Task { await viewModel.refresh() } }
            )
        } else if let message = viewModel.errorMessage {
            JarvisStateBanner(
                title: "Connection problem",
                message: message,
                systemImage: "exclamationmark.triangle",
                tone: .error,
                actionTitle: "Try again",
                action: { Task { await viewModel.refresh() } }
            )
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.xs) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(JarvisTheme.accent)
                .padding(.bottom, JarvisTheme.Spacing.xs)

            Text("What can JARVIS help with?")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(JarvisTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Code, plan, debug, and build with your personal assistant.")
                .font(JarvisTheme.Typography.body)
                .foregroundStyle(JarvisTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, JarvisTheme.Spacing.xxl)
        .padding(.bottom, JarvisTheme.Spacing.xl)
    }

    private var promptSuggestions: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            alignment: .leading,
            spacing: JarvisTheme.Spacing.xs
        ) {
            ForEach(suggestedPrompts, id: \.self) { prompt in
                Button {
                    draft = prompt
                } label: {
                    Text(prompt)
                        .font(JarvisTheme.Typography.metadata)
                        .foregroundStyle(JarvisTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, JarvisTheme.Spacing.sm)
                        .padding(.vertical, JarvisTheme.Spacing.xs)
                        .background(JarvisTheme.surface, in: .capsule)
                        .overlay {
                            Capsule().stroke(JarvisTheme.border, lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use suggested prompt: \(prompt)")
            }
        }
        .padding(.bottom, JarvisTheme.Spacing.md)
    }

    private var homeComposer: some View {
        ComposerView(
            text: $draft,
            placeholder: "Ask JARVIS anything…",
            isStreaming: false,
            onSend: { Task { await createConversation() } },
            onCancel: {},
            onAttachment: { showAttachmentNotice = true }
        )
        .disabled(isCreatingConversation)
        .opacity(isCreatingConversation ? 0.65 : 1)
        .padding(.horizontal, -JarvisTheme.Spacing.sm)
    }

    private var recentConversations: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("RECENT CONVERSATIONS")
                    .font(JarvisTheme.Typography.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(JarvisTheme.textTertiary)

                Spacer()

                Button("See all") {
                    presentHistory = true
                }
                .font(JarvisTheme.Typography.metadata.weight(.medium))
                .foregroundStyle(JarvisTheme.accent)
            }
            .padding(.top, JarvisTheme.Spacing.xxl)
            .padding(.bottom, JarvisTheme.Spacing.xs)

            ForEach(viewModel.recentSessions) { session in
                recentSessionRow(session)
            }
        }
    }

    @ViewBuilder
    private func recentSessionRow(_ session: Session) -> some View {
        if session.is_streaming == true {
            Button {
                streamingLockedSession = session
            } label: {
                SessionRow(session: session)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: ConversationRoute(session: session, initialMessage: nil)) {
                SessionRow(session: session)
            }
            .buttonStyle(.plain)
        }
    }

    private func createConversation() async {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isCreatingConversation else { return }

        isCreatingConversation = true
        defer { isCreatingConversation = false }

        guard let session = await viewModel.newSession() else { return }
        draft = ""
        path.append(ConversationRoute(session: session, initialMessage: message))
    }
}

struct SessionHistoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(APIConfig.self) private var apiConfig
    @Environment(\.dismiss) private var dismiss
    @Bindable private var viewModel: SessionListViewModel
    @State private var renaming: Session?
    @State private var renameDraft = ""
    @State private var streamingLockedSession: Session?
    @State private var path = NavigationPath()

    init(viewModel: SessionListViewModel) {
        self._viewModel = Bindable(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if viewModel.isLoading && viewModel.sessions.isEmpty {
                    JarvisHistorySkeleton()
                        .padding(.horizontal, JarvisTheme.Spacing.md)
                } else if viewModel.sessions.isEmpty {
                    JarvisEmptyState(
                        systemImage: viewModel.errorMessage == nil ? "bubble.left.and.bubble.right" : "wifi.exclamationmark",
                        title: viewModel.errorMessage == nil ? "No conversations yet" : "History is unavailable",
                        message: viewModel.errorMessage == nil
                            ? "Start a new conversation from the JARVIS home screen."
                            : "We couldn't load your conversation history. Check your connection and try again.",
                        actionTitle: viewModel.errorMessage == nil ? nil : "Try again",
                        action: viewModel.errorMessage == nil ? nil : { Task { await viewModel.refresh() } }
                    )
                    .padding(.horizontal, JarvisTheme.Spacing.md)
                    .padding(.top, JarvisTheme.Spacing.xl)
                } else {
                    List {
                        ForEach(viewModel.grouped) { group in
                            Section {
                                ForEach(group.items) { session in
                                    sessionRow(session)
                                        .buttonStyle(.plain)
                                        .listRowBackground(JarvisTheme.background)
                                        .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
                                        .listRowSeparator(.hidden)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                Task { await viewModel.delete(session) }
                                            } label: { Label("Delete", systemImage: "trash") }
                                            Button {
                                                renaming = session
                                                renameDraft = session.title
                                            } label: { Label("Rename", systemImage: "pencil") }
                                            .tint(.blue)
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                Task { await viewModel.togglePin(session) }
                                            } label: {
                                                Label(session.pinned ? "Unpin" : "Pin", systemImage: session.pinned ? "pin.slash" : "pin")
                                            }
                                            .tint(.yellow)
                                            Button {
                                                Task { await viewModel.toggleArchive(session) }
                                            } label: { Label("Archive", systemImage: "archivebox") }
                                            .tint(.gray)
                                        }
                                }
                            } header: {
                                Text(group.title.uppercased())
                                    .font(JarvisTheme.Typography.eyebrow)
                                    .tracking(0.8)
                                    .foregroundStyle(JarvisTheme.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, JarvisTheme.Spacing.lg)
                                    .padding(.bottom, JarvisTheme.Spacing.xs)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                }
            }
            .background(JarvisTheme.background.ignoresSafeArea())
            .refreshable { await viewModel.refresh() }
            .navigationTitle("All conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(JarvisTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if appState.reachability == .offline {
                    JarvisStateBanner(
                        title: "Offline mode",
                        message: "Showing saved history until the connection returns.",
                        systemImage: "wifi.slash",
                        tone: .warning,
                        actionTitle: "Retry",
                        action: { Task { await viewModel.refresh() } }
                    )
                    .padding(.horizontal, JarvisTheme.Spacing.md)
                    .padding(.top, JarvisTheme.Spacing.xs)
                    .padding(.bottom, JarvisTheme.Spacing.sm)
                } else if let message = viewModel.errorMessage {
                    JarvisStateBanner(
                        title: "Couldn't update history",
                        message: message,
                        systemImage: "exclamationmark.triangle",
                        tone: .error,
                        actionTitle: "Try again",
                        action: { Task { await viewModel.refresh() } }
                    )
                    .padding(.horizontal, JarvisTheme.Spacing.md)
                    .padding(.top, JarvisTheme.Spacing.xs)
                    .padding(.bottom, JarvisTheme.Spacing.sm)
                }
            }
            .navigationDestination(for: ConversationRoute.self) { route in
                ConversationView(
                    sessionID: route.session.session_id,
                    title: route.session.title,
                    initialMessage: route.initialMessage
                )
                .environment(apiConfig)
            }
            .alert("Rename conversation", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            ), presenting: renaming) { _ in
                TextField("Title", text: $renameDraft)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if let session = renaming {
                        let title = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            if !title.isEmpty {
                                await viewModel.rename(session.session_id, to: title)
                            }
                            renaming = nil
                        }
                    }
                }
            }
            .alert(
                "Conversation is streaming",
                isPresented: Binding(
                    get: { streamingLockedSession != nil },
                    set: { if !$0 { streamingLockedSession = nil } }
                ),
                presenting: streamingLockedSession
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { session in
                Text("'\(session.title)' is actively streaming on another device. Wait for the current turn to finish, then try again.")
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func sessionRow(_ session: Session) -> some View {
        if session.is_streaming == true {
            Button {
                streamingLockedSession = session
            } label: {
                SessionRow(session: session)
            }
        } else {
            NavigationLink(value: ConversationRoute(session: session, initialMessage: nil)) {
                SessionRow(session: session)
            }
        }
    }
}

// Kept as a compatibility wrapper for previews and older debug launch flows.
struct SessionListView: View {
    var body: some View { HomeView() }
}

private struct SessionRow: View {
    let session: Session

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: JarvisTheme.Spacing.sm) {
                Image(systemName: session.is_streaming == true ? "circle.dotted" : "bubble.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(session.is_streaming == true ? JarvisTheme.accent : JarvisTheme.textSecondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(session.title)
                            .font(JarvisTheme.Typography.rowTitle)
                            .foregroundStyle(JarvisTheme.textPrimary)
                            .lineLimit(1)
                        if session.pinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                    }
                    HStack(spacing: 6) {
                        Text("\(session.message_count) messages")
                        if let cost = session.estimated_cost {
                            Text(String(format: "$%.2f", cost))
                        }
                        if let model = session.model, !model.isEmpty {
                            Text("·")
                            Text(model.split(separator: "/").last.map(String.init) ?? model)
                                .lineLimit(1)
                        }
                    }
                    .font(JarvisTheme.Typography.metadata)
                    .foregroundStyle(JarvisTheme.textSecondary)
                }

                Spacer(minLength: JarvisTheme.Spacing.sm)
                Text(session.displayTimestamp, style: .relative)
                    .font(.system(size: 12))
                    .foregroundStyle(JarvisTheme.textTertiary)
            }
            .padding(.vertical, JarvisTheme.Spacing.md)

            Rectangle()
                .fill(JarvisTheme.divider)
                .frame(height: 1)
                .padding(.leading, 36)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.title), \(session.message_count) messages")
    }
}
