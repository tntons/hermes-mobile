//
//  SessionListView.swift
//  Hermes
//

import SwiftUI

struct SessionListView: View {
    @Environment(AppState.self) private var appState
    @Environment(APIConfig.self) private var apiConfig
    @State private var viewModel = SessionListViewModel()
    @State private var presentingConversationFor: Session?
    @State private var showNew: Bool = false
    @State private var renaming: Session?
    @State private var renameDraft: String = ""

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.sessions.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "No sessions yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Tap **+** to start a conversation with Hermes.")
                    )
                } else {
                    List {
                        ForEach(viewModel.grouped) { group in
                            Section(group.title) {
                                ForEach(group.items) { session in
                                    Button {
                                        presentingConversationFor = session
                                    } label: {
                                        SessionRow(session: session)
                                    }
                                    .buttonStyle(.plain)
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
                                        } label: { Label(session.pinned ? "Unpin" : "Pin", systemImage: session.pinned ? "pin.slash" : "pin") }
                                        .tint(.yellow)
                                        Button {
                                            Task { await viewModel.toggleArchive(session) }
                                        } label: { Label("Archive", systemImage: "archivebox") }
                                        .tint(.gray)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .refreshable { await viewModel.refresh() }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        presentSettings = true
                    } label: { Image(systemName: "gear") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            if let s = await viewModel.newSession() {
                                presentingConversationFor = s
                            }
                        }
                    } label: { Image(systemName: "plus") }
                }
            }
            .overlay(alignment: .bottom) {
                if let msg = viewModel.errorMessage {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .padding()
                        .background(Color.secondary.opacity(0.15), in: .rect(cornerRadius: 8))
                        .padding()
                }
            }
            .navigationDestination(item: $presentingConversationFor) { session in
                ConversationView(sessionID: session.session_id, title: session.title)
                    .environment(apiConfig)
            }
            .alert("Rename session",
                   isPresented: Binding(
                        get: { renaming != nil },
                        set: { if !$0 { renaming = nil } }
                   ),
                   presenting: renaming
            ) { _ in
                TextField("Title", text: $renameDraft)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if let s = renaming {
                        let title = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            if !title.isEmpty {
                                await viewModel.rename(s.session_id, to: title)
                            }
                            renaming = nil
                        }
                    }
                }
            }
            .sheet(isPresented: $presentSettings) {
                SettingsView()
                    .environment(appState)
                    .environment(apiConfig)
            }
            .task {
                await viewModel.bootstrap(config: apiConfig)
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-openFirstSession"),
                   let first = viewModel.sessions.first,
                   presentingConversationFor == nil {
                    presentingConversationFor = first
                }
                #endif
            }
        }
    }

    @State private var presentSettings: Bool = false
}

private struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15))
                Image(systemName: "bubble.left")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(.headline)
                        .lineLimit(1)
                    if session.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.yellow) }
                    if let m = session.model, !m.isEmpty {
                        Text(m.split(separator: "/").last.map(String.init) ?? m)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: .capsule)
                    }
                }
                HStack {
                    Text("\(session.message_count) messages")
                    if let cost = session.estimated_cost {
                        Text(String(format: "$%.2f", cost))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(session.displayTimestamp, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
