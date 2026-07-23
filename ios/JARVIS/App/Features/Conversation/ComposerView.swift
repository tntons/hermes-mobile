//
//  ComposerView.swift
//  JARVIS
//

import SwiftUI

struct ComposerView: View {
    @Binding var text: String
    var placeholder: String = "Message JARVIS…"
    let isStreaming: Bool
    let onSend: () -> Void
    let onCancel: () -> Void
    let onAttachment: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: JarvisTheme.Spacing.xs) {
            HStack(alignment: .bottom, spacing: JarvisTheme.Spacing.xs) {
                Button(action: onAttachment) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(JarvisTheme.textSecondary)
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel("Add attachment")

                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .font(.system(size: 16))
                    // 16 pt font prevents iOS zoom-on-focus (must not drop below 16 for the field).
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(JarvisTheme.textPrimary)
                    .tint(JarvisTheme.accent)
                    .accessibilityValue(text.isEmpty ? "Empty" : text)
                    .accessibilityHint(text.isEmpty ? "Enter a message to enable Send." : "Ready to send.")
                Spacer(minLength: 0)
                actionButton
            }
            .padding(.leading, JarvisTheme.Spacing.sm)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(JarvisTheme.surface, in: .rect(cornerRadius: JarvisTheme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: JarvisTheme.Radius.card)
                    .stroke(JarvisTheme.border, lineWidth: 0.5)
            }
        }
        .padding(.horizontal, JarvisTheme.Spacing.sm)
        .padding(.top, JarvisTheme.Spacing.xs)
        .safeAreaPadding(.bottom, 4)
        .background(JarvisTheme.background)
    }

    @ViewBuilder
    private var actionButton: some View {
        if isStreaming {
            Button(action: onCancel) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(JarvisTheme.textPrimary, in: .circle)
            }
            .accessibilityLabel("Stop response")
        } else {
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(canSend ? .black : JarvisTheme.textTertiary)
                    .frame(width: 34, height: 34)
                    .background(canSend ? JarvisTheme.textPrimary : JarvisTheme.surfaceElevated, in: .circle)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send message")
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
