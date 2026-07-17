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
            Divider().overlay(HermesTheme.border)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message Hermes…", text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .font(.system(size: 16))
                    // 16 pt font prevents iOS zoom-on-focus (must not drop below 16 for the field).
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(HermesTheme.textPrimary)
                    .tint(HermesTheme.accent)
                    .background(HermesTheme.surface, in: .capsule)
                    .overlay(Capsule().stroke(HermesTheme.border, lineWidth: 0.5))
                if isStreaming {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 32, height: 32)
                            .background(HermesTheme.textPrimary, in: .circle)
                    }
                } else {
                    Button {
                        onSend()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(canSend ? .black : HermesTheme.textTertiary)
                            .frame(width: 32, height: 32)
                            .background(canSend ? HermesTheme.textPrimary : HermesTheme.surfaceElevated, in: .circle)
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .safeAreaPadding(.bottom, 4)
        }
        .background(HermesTheme.background)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
