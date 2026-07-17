//
//  CodeBlockView.swift
//  Hermes
//
//  Native code block with a header strip (language label + copy button)
//  and a syntax-highlighted body. Mirrors the Hermes Desktop's CodeCard
//  treatment without any webview / JS bridge.
//

import SwiftUI
import UIKit

struct CodeBlockView: View {
    let language: String?
    let code: String

    @State private var copyState: CopyState = .idle

    private enum CopyState {
        case idle
        case copied
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            bodyView
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.22), lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text((language ?? "code").uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button {
                UIPasteboard.general.string = code
                copyState = .copied
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    copyState = .idle
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: copyState == .copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                    if copyState == .copied {
                        Text("Copied")
                            .font(.caption2.weight(.medium))
                    }
                }
                .foregroundStyle(copyState == .copied ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(height: 0.5)
        }
    }

    private var bodyView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(SyntaxHighlighter.highlight(code, language: language))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineSpacing(2)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
