//
//  ConversationView.swift
//  Hermes
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
                MessageListView(
                    messages: $viewModel.messages,
                    isStreaming: viewModel.isStreaming,
                    onRegenerate: { Task { await viewModel.regenerateLastResponse() } }
                )
                ComposerView(
                    text: $viewModel.composerText,
                    isStreaming: viewModel.isStreaming,
                    onSend: { Task { await viewModel.send() } },
                    onCancel: { Task { await viewModel.cancelStream() } },
                    onAttachment: { showAttachmentNotice = true }
                )
            }
            if let msg = viewModel.errorMessage {
                VStack {
                    HStack {
                        Label(msg, systemImage: "exclamationmark.triangle")
                            .padding(8)
                            .background(HermesTheme.surface, in: .rect(cornerRadius: HermesTheme.Radius.small))
                            .overlay {
                                RoundedRectangle(cornerRadius: HermesTheme.Radius.small)
                                    .stroke(HermesTheme.border, lineWidth: 0.5)
                            }
                        Spacer()
                        Button("Dismiss") { viewModel.errorMessage = nil }
                            .padding(8)
                    }
                    .padding(.horizontal)
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
        .background(HermesTheme.background.ignoresSafeArea())
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
                        let client = HermesClient(config: .init(gatewayURL: url, bearerToken: token))
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
                Task { await viewModel.resumeIfNeeded() }
            }
        }
    }
}
