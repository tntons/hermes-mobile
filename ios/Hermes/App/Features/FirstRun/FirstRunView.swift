//
//  FirstRunView.swift
//  Hermes
//

import SwiftUI

struct FirstRunView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = FirstRunViewModel()
    @FocusState private var focused: Field?
    private enum Field: Hashable { case url, token, profile }

    var body: some View {
        NavigationStack {
            Form {
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
                    Button {
                        Task { await viewModel.saveAndContinue(appState: appState) }
                    } label: {
                        Text("Save and continue")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Section {
                    Text("Tokens are stored in the iOS Keychain and never leave your device. Point your bridge's `cloudflared` tunnel at your host, then paste the public URL above plus your `MOBILE_TOKEN`.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Welcome")
        }
    }
}
