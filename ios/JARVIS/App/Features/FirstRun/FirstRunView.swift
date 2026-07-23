//
//  FirstRunView.swift
//  JARVIS
//

import SwiftUI

struct FirstRunView: View {
    @Environment(AppState.self) private var appState
    @Environment(APIConfig.self) private var apiConfig
    @State private var viewModel = FirstRunViewModel()
    @FocusState private var focused: Field?
    private enum Field: Hashable { case url, token, profile }
    private let onFinished: () -> Void

    init(onFinished: @escaping () -> Void = {}) {
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
#if DEBUG
                    Section("Preview") {
                        Button {
                            viewModel.continueAsMock(appState: appState)
                            apiConfig.reload()
                            onFinished()
                        } label: {
                            Label("Continue as demo user", systemImage: "person.crop.circle.badge.checkmark")
                        }
                        Text("Uses local sample data and does not require a connection.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
#endif
                    Section("Connection") {
                        TextField("Connection URL (https://…)", text: $viewModel.gatewayURLString)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .focused($focused, equals: .url)
                        TextField("Access token", text: $viewModel.bearerToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .token)
                        TextField("Profile (optional)", text: $viewModel.profile)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .profile)
                    }
                    Section {
                        Button {
                            Task { await viewModel.testConnection() }
                        } label: {
                            HStack {
                                if viewModel.isTesting { ProgressView() } else { Image(systemName: "antenna.radiowaves.left.and.right") }
                                Text(viewModel.isTesting ? "Testing…" : "Test connection")
                                    .padding(.leading, 4)
                            }
                        }
                        .disabled(viewModel.isTesting || viewModel.gatewayURLString.isEmpty || viewModel.bearerToken.isEmpty)
                    }
                    if let r = viewModel.testResult {
                        Section {
                            switch r {
                            case .success:
                                JarvisStateBanner(
                                    title: "Connection ready",
                                    message: "JARVIS reached the gateway successfully.",
                                    systemImage: "checkmark.circle.fill",
                                    tone: .success
                                )
                            case .failure(let message):
                                JarvisStateBanner(
                                    title: "Connection failed",
                                    message: message,
                                    systemImage: "wifi.exclamationmark",
                                    tone: .error
                                )
                            }
                        }
                    }
                    if let msg = viewModel.errorMessage {
                        Section {
                            JarvisStateBanner(
                                title: "Configuration needs attention",
                                message: msg,
                                systemImage: "exclamationmark.triangle",
                                tone: .error
                            )
                        }
                    }
                    Section {
                        Text("Your access token is stored securely on this device. Paste your public connection URL and access token to connect JARVIS.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(JarvisTheme.background)

                Button {
                    Task {
                        await viewModel.saveAndContinue(appState: appState)
                        if viewModel.errorMessage == nil {
                            apiConfig.reload()
                            onFinished()
                        }
                    }
                } label: {
                    Text("Save and continue")
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.gatewayURLString.isEmpty || viewModel.bearerToken.isEmpty)
                .padding(.horizontal)
                .padding(.bottom, 12)
                .padding(.top, 8)
                .background(JarvisTheme.background)
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(JarvisTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
