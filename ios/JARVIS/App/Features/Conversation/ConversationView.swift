//
//  ConversationView.swift
//  JARVIS
//

import SwiftUI

struct ConversationView: View {
    @Environment(AppState.self) private var appState
    @Environment(APIConfig.self) private var apiConfig
    @State var sessionID: String
    @State var title: String
    @State private var viewModel: ConversationViewModel
    @State private var renaming: Bool = false
    @State private var renameDraft: String = ""
    @State private var showAttachmentNotice: Bool = false
    @FocusState private var composerFocused: Bool

    init(sessionID: String, title: String, initialMessage: String? = nil) {
        _sessionID = State(initialValue: sessionID)
        _title = State(initialValue: title)
        _viewModel = State(initialValue: ConversationViewModel(
            sessionID: sessionID,
            title: title,
            initialMessage: initialMessage
        ))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if let error = viewModel.errorMessage {
                    JarvisStateBanner(
                        title: "Message not sent",
                        message: error,
                        systemImage: "exclamationmark.triangle",
                        tone: .error,
                        actionTitle: "Dismiss",
                        action: { viewModel.errorMessage = nil }
                    )
                    .padding(.horizontal, JarvisTheme.Spacing.sm)
                    .padding(.top, JarvisTheme.Spacing.xs)
                }

                if appState.reachability == .offline {
                    JarvisStateBanner(
                        title: "Offline mode",
                        message: "Saved messages remain available. Sending is paused until the connection returns.",
                        systemImage: "wifi.slash",
                        tone: .warning,
                        actionTitle: "Retry history",
                        action: { Task { await viewModel.refreshHistory() } }
                    )
                    .padding(.horizontal, JarvisTheme.Spacing.sm)
                    .padding(.top, JarvisTheme.Spacing.xs)
                } else if viewModel.historyErrorMessage != nil {
                    JarvisStateBanner(
                        title: "Couldn't refresh conversation",
                        message: "\(viewModel.historyErrorMessage ?? "History is temporarily unavailable.") Showing saved messages instead.",
                        systemImage: "arrow.triangle.2.circlepath",
                        tone: .error,
                        actionTitle: "Try again",
                        action: { Task { await viewModel.refreshHistory() } }
                    )
                    .padding(.horizontal, JarvisTheme.Spacing.sm)
                    .padding(.top, JarvisTheme.Spacing.xs)
                }

                if viewModel.isLoadingHistory && viewModel.messages.isEmpty {
                    JarvisConversationSkeleton()
                        .padding(.horizontal, JarvisTheme.Spacing.lg)
                } else if viewModel.messages.isEmpty {
                    JarvisEmptyState(
                        systemImage: "sparkles",
                        title: "Start the conversation",
                        message: "Ask JARVIS to explain, plan, debug, or build something for you."
                    )
                    .padding(.horizontal, JarvisTheme.Spacing.lg)
                    .padding(.vertical, JarvisTheme.Spacing.xl)
                    .frame(maxHeight: .infinity)
                } else {
                    MessageListView(
                        messages: $viewModel.messages,
                        isStreaming: viewModel.isStreaming,
                        onRegenerate: { Task { await viewModel.regenerateLastResponse() } },
                        onApprovalDecision: { approvalID, decision in
                            Task { await viewModel.decideApproval(approvalID: approvalID, decision: decision) }
                        }
                    )
                }
                ComposerView(
                    text: $viewModel.composerText,
                    isStreaming: viewModel.isStreaming,
                    onSend: { Task { await viewModel.send() } },
                    onCancel: { Task { await viewModel.cancelStream() } },
                    onAttachment: { showAttachmentNotice = true }
                )
            }
        }
        .background(JarvisTheme.background.ignoresSafeArea())
        .navigationTitle(viewModel.titleDraft)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.bar, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    renaming = true
                    renameDraft = viewModel.titleDraft
                } label: { Image(systemName: "pencil") }
            }
        }
        .alert("Rename conversation", isPresented: $renaming) {
            TextField("Title", text: $renameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let t = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    viewModel.titleDraft = t
                    if apiConfig.isMock { return }
                    // Fire-and-forget; v1 doesn't surface a failed-rename toast.
                    Task {
                        guard apiConfig.isConfigured,
                              let url = apiConfig.gatewayURL,
                              let token = apiConfig.bearerToken
                        else { return }
                        let client = JarvisClient(config: .init(gatewayURL: url, bearerToken: token))
                        try? await client.renameSession(sessionID: viewModel.sessionID, to: t)
                    }
                }
            }
        }
        .alert("Attachments", isPresented: $showAttachmentNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Mobile file and photo uploads are not available yet. The attachment control is ready for a future update.")
        }
        .task {
            await viewModel.bootstrap(config: apiConfig)
            await viewModel.resumeIfNeeded()
            await viewModel.sendInitialMessageIfNeeded()
        }
        .onChange(of: appState.scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await viewModel.resumeIfNeeded()
                    await viewModel.refreshPendingApprovals()
                }
            }
        }
    }
}
