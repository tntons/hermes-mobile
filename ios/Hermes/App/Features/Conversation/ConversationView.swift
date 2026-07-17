//
//  ConversationView.swift
//  Hermes
//

import SwiftUI

struct ConversationView: View {
    @Environment(AppState.self) private var appState
    @Environment(APIConfig.self) private var apiConfig
    @Environment(\.dismiss) private var dismiss
    @State var sessionID: String
    @State var title: String
    @State private var viewModel: ConversationViewModel
    @State private var renaming: Bool = false
    @State private var renameDraft: String = ""
    @FocusState private var composerFocused: Bool

    init(sessionID: String, title: String) {
        _sessionID = State(initialValue: sessionID)
        _title = State(initialValue: title)
        _viewModel = State(initialValue: ConversationViewModel(sessionID: sessionID, title: title))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                MessageListView(messages: $viewModel.messages, isStreaming: viewModel.isStreaming)
                ComposerView(
                    text: $viewModel.composerText,
                    isStreaming: viewModel.isStreaming,
                    onSend: { Task { await viewModel.send() } },
                    onCancel: { Task { await viewModel.cancelStream() } }
                )
            }
            if let msg = viewModel.errorMessage {
                VStack {
                    HStack {
                        Label(msg, systemImage: "exclamationmark.triangle")
                            .padding(8)
                            .background(.thinMaterial, in: .rect(cornerRadius: 8))
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
        .navigationTitle(viewModel.titleDraft)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.bar, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.medium))
                        Text("Sessions")
                            .font(.body)
                    }
                    .foregroundStyle(.tint)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    renaming = true
                    renameDraft = viewModel.titleDraft
                } label: { Image(systemName: "pencil") }
            }
        }
        .alert("Rename session", isPresented: $renaming) {
            TextField("Title", text: $renameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let t = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    viewModel.titleDraft = t
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
        .task {
            await viewModel.bootstrap(config: apiConfig)
            await viewModel.resumeIfNeeded()
        }
        .onChange(of: appState.scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await viewModel.resumeIfNeeded() }
            }
        }
    }
}
