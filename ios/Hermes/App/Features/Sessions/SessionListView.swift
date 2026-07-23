//
//  SessionListView.swift
//  Hermes
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
                    promptSuggestions
                    homeComposer

                    if viewModel.isLoading && viewModel.sessions.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, HermesTheme.Spacing.xl)
                    } else if !viewModel.recentSessions.isEmpty {
                        recentConversations
                    }
                }
                .padding(.horizontal, HermesTheme.Spacing.md)
                .padding(.bottom, HermesTheme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .background(HermesTheme.background.ignoresSafeArea())
            .refreshable { await viewModel.refresh() }
            .navigationTitle("Hermes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(HermesTheme.background, for: .navigationBar)
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
            .overlay(alignment: .bottom) {
                if let msg = viewModel.errorMessage {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .font(HermesTheme.Typography.metadata)
                        .padding()
                        .background(HermesTheme.surface, in: .rect(cornerRadius: HermesTheme.Radius.small))
                        .overlay {
                            RoundedRectangle(cornerRadius: HermesTheme.Radius.small)
                                .stroke(HermesTheme.border, lineWidth: 0.5)
                        }
                    .padding()
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

    private var hero: some View {
        VStack(alignment: .leading, spacing: HermesTheme.Spacing.xs) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(HermesTheme.accent)
                .padding(.bottom, HermesTheme.Spacing.xs)

            Text("What can Hermes help with?")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(HermesTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Code, plan, debug, and build with your personal assistant.")
                .font(HermesTheme.Typography.body)
                .foregroundStyle(HermesTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, HermesTheme.Spacing.xxl)
        .padding(.bottom, HermesTheme.Spacing.xl)
    }

    private var promptSuggestions: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            alignment: .leading,
            spacing: HermesTheme.Spacing.xs
        ) {
            ForEach(suggestedPrompts, id: \.self) { prompt in
                Button {
                    draft = prompt
                } label: {
                    Text(prompt)
                        .font(HermesTheme.Typography.metadata)
                        .foregroundStyle(HermesTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, HermesTheme.Spacing.sm)
                        .padding(.vertical, HermesTheme.Spacing.xs)
                        .background(HermesTheme.surface, in: .capsule)
                        .overlay {
                            Capsule().stroke(HermesTheme.border, lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use suggested prompt: \(prompt)")
            }
        }
        .padding(.bottom, HermesTheme.Spacing.md)
    }

    private var homeComposer: some View {
        ComposerView(
            text: $draft,
            placeholder: "Ask Hermes anything…",
            isStreaming: false,
            onSend: { Task { await createConversation() } },
            onCancel: {},
            onAttachment: { showAttachmentNotice = true }
        )
        .disabled(isCreatingConversation)
        .opacity(isCreatingConversation ? 0.65 : 1)
        .padding(.horizontal, -HermesTheme.Spacing.sm)
    }

    private var recentConversations: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("RECENT CONVERSATIONS")
                    .font(HermesTheme.Typography.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(HermesTheme.textTertiary)

                Spacer()

                Button("See all") {
                    presentHistory = true
                }
                .font(HermesTheme.Typography.metadata.weight(.medium))
                .foregroundStyle(HermesTheme.accent)
            }
            .padding(.top, HermesTheme.Spacing.xxl)
            .padding(.bottom, HermesTheme.Spacing.xs)

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
                if viewModel.sessions.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "No conversations yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start a new conversation from the Hermes home screen.")
                    )
                } else {
                    List {
                        ForEach(viewModel.grouped) { group in
                            Section {
                                ForEach(group.items) { session in
                                    sessionRow(session)
                                        .buttonStyle(.plain)
                                        .listRowBackground(HermesTheme.background)
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
                                    .font(HermesTheme.Typography.eyebrow)
                                    .tracking(0.8)
                                    .foregroundStyle(HermesTheme.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, HermesTheme.Spacing.lg)
                                    .padding(.bottom, HermesTheme.Spacing.xs)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                }
            }
            .background(HermesTheme.background.ignoresSafeArea())
            .refreshable { await viewModel.refresh() }
            .navigationTitle("All conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(HermesTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let msg = viewModel.errorMessage {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .font(HermesTheme.Typography.metadata)
                        .padding()
                        .background(HermesTheme.surface, in: .rect(cornerRadius: HermesTheme.Radius.small))
                        .padding()
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
            HStack(spacing: HermesTheme.Spacing.sm) {
                Image(systemName: session.is_streaming == true ? "circle.dotted" : "bubble.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(session.is_streaming == true ? HermesTheme.accent : HermesTheme.textSecondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(session.title)
                            .font(HermesTheme.Typography.rowTitle)
                            .foregroundStyle(HermesTheme.textPrimary)
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
                    .font(HermesTheme.Typography.metadata)
                    .foregroundStyle(HermesTheme.textSecondary)
                }

                Spacer(minLength: HermesTheme.Spacing.sm)
                Text(session.displayTimestamp, style: .relative)
                    .font(.system(size: 12))
                    .foregroundStyle(HermesTheme.textTertiary)
            }
            .padding(.vertical, HermesTheme.Spacing.md)

            Rectangle()
                .fill(HermesTheme.divider)
                .frame(height: 1)
                .padding(.leading, 36)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.title), \(session.message_count) messages")
    }
}
