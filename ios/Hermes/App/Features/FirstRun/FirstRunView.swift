//
//  FirstRunView.swift
//  Hermes
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
                        Text("Uses local sample data and does not require a bridge.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
#endif
                    Section("Bridge") {
                        TextField("Gateway URL (https://…)", text: $viewModel.gatewayURLString)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .focused($focused, equals: .url)
                        TextField("Bearer token", text: $viewModel.bearerToken)
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

                        if let r = viewModel.testResult {
                            switch r {
                            case .success:
                                Label("Connection OK", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            case .failure(let s):
                                Label(s, systemImage: "xmark.octagon.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    if let msg = viewModel.errorMessage {
                        Section { Text(msg).foregroundStyle(.red) }
                    }
                    Section {
                        Text("Tokens are stored in the iOS Keychain and never leave your device. Point your bridge's `cloudflared` tunnel at your host, then paste the public URL above plus your `MOBILE_TOKEN`.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

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
                .background(.bar)
            }
            .navigationTitle("Welcome")
        }
    }
}
