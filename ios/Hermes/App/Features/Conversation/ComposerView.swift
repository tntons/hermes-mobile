//
//  ComposerView.swift
//  Hermes
//

import SwiftUI

struct ComposerView: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message Hermes…", text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .font(.body)
                    // 16 pt font prevents iOS zoom-on-focus (must not drop below 16 for the field).
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.10), in: .capsule)
                if isStreaming {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                } else {
                    Button {
                        onSend()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.title2)
                            .foregroundStyle(canSend ? Color.accentColor : .secondary)
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .safeAreaPadding(.bottom, 4)
        }
        .background(.bar)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
