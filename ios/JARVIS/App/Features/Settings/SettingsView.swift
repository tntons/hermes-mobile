//
//  SettingsView.swift
//  JARVIS
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(APIConfig.self) private var apiConfig
    @Environment(\.dismiss) private var dismiss

    @State private var showReauth: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section(apiConfig.isMock ? "Demo account" : "Connection") {
                    if apiConfig.isMock {
                        LabeledContent("Account", value: "Demo user")
                        Text("Running with local sample data. No connection is required.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Connection URL") {
                            Text(apiConfig.gatewayURL?.absoluteString ?? "—")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .font(.caption.monospaced())
                        }
                        LabeledContent("Access token") {
                            Text(maskToken(apiConfig.bearerToken))
                                .font(.caption.monospaced())
                        }
                    }
                    if let profile = KeychainStore.shared.profile, !profile.isEmpty {
                        LabeledContent("Profile", value: profile)
                    }
                    Button {
                        showReauth = true
                    } label: {
                        Label("Edit connection", systemImage: "pencil")
                    }
                }
                Section("Appearance") {
                    LabeledContent("Theme", value: "System (follow device)")
                }
                Section {
                    Button(role: .destructive) {
                        KeychainStore.shared.wipe()
                        apiConfig.reload()
                        appState.reloadAuth()
                        dismiss()
                    } label: {
                        Label("Disconnect JARVIS", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } footer: {
                    Text("Disconnecting removes the saved connection details from this device. Your server-side conversations and history remain untouched.")
                }
                Section("Build") {
                    LabeledContent("App", value: "\(JarvisBrand.displayName) v0.1.0")
                    LabeledContent("Connection", value: JarvisBrand.displayName)
                }
            }
            .scrollContentBackground(.hidden)
            .background(JarvisTheme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(JarvisTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(JarvisTheme.accent)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showReauth) {
                FirstRunView {
                    showReauth = false
                    dismiss()
                }
                    .environment(appState)
                    .environment(apiConfig)
            }
        }
    }

    private func maskToken(_ token: String?) -> String {
        guard let t = token, t.count > 6 else { return "— ···" }
        let head = t.prefix(3)
        let tail = t.suffix(3)
        return "\(head)…\(tail) (\(t.count) chars)"
    }
}
