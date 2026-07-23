//
//  ComposerView.swift
//  Hermes
//

import SwiftUI

struct ComposerView: View {
    @Binding var text: String
    var placeholder: String = "Message Hermes…"
    let isStreaming: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: HermesTheme.Spacing.xs) {
            HStack(alignment: .bottom, spacing: HermesTheme.Spacing.xs) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .font(.system(size: 16))
                    // 16 pt font prevents iOS zoom-on-focus (must not drop below 16 for the field).
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(HermesTheme.textPrimary)
                    .tint(HermesTheme.accent)
                Spacer(minLength: 0)
                actionButton
            }
            .padding(.leading, HermesTheme.Spacing.sm)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(HermesTheme.surface, in: .rect(cornerRadius: HermesTheme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: HermesTheme.Radius.card)
                    .stroke(HermesTheme.border, lineWidth: 0.5)
            }
        }
        .padding(.horizontal, HermesTheme.Spacing.sm)
        .padding(.top, HermesTheme.Spacing.xs)
        .safeAreaPadding(.bottom, 4)
        .background(HermesTheme.background)
    }

    @ViewBuilder
    private var actionButton: some View {
        if isStreaming {
            Button(action: onCancel) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(HermesTheme.textPrimary, in: .circle)
            }
            .accessibilityLabel("Stop response")
        } else {
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(canSend ? .black : HermesTheme.textTertiary)
                    .frame(width: 34, height: 34)
                    .background(canSend ? HermesTheme.textPrimary : HermesTheme.surfaceElevated, in: .circle)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send message")
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
