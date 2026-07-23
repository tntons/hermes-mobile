//
//  JarvisStateViews.swift
//  JARVIS
//
//  Reusable state surfaces for loading, empty, connection, and live-work
//  states. These keep transient product state visible without relying on
//  temporary toast-style overlays.
//

import SwiftUI

enum JarvisStateTone {
    case neutral
    case info
    case success
    case warning
    case error

    var tint: Color {
        switch self {
        case .neutral: return JarvisTheme.textSecondary
        case .info: return JarvisTheme.accent
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    var fill: Color {
        switch self {
        case .neutral: return JarvisTheme.surface
        case .info: return JarvisTheme.accentSoft.opacity(0.20)
        case .success: return Color.green.opacity(0.12)
        case .warning: return Color.orange.opacity(0.13)
        case .error: return Color.red.opacity(0.13)
        }
    }

    var border: Color {
        switch self {
        case .neutral: return JarvisTheme.border
        case .info: return JarvisTheme.accent.opacity(0.25)
        case .success: return Color.green.opacity(0.25)
        case .warning: return Color.orange.opacity(0.28)
        case .error: return Color.red.opacity(0.28)
        }
    }
}

struct JarvisStateBanner: View {
    let title: String
    let message: String
    let systemImage: String
    let tone: JarvisStateTone
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        title: String,
        message: String,
        systemImage: String,
        tone: JarvisStateTone = .neutral,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tone = tone
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top, spacing: JarvisTheme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tone.tint)
                .frame(width: 24, height: 24)
                .background(tone.tint.opacity(0.14), in: .circle)

            VStack(alignment: .leading, spacing: JarvisTheme.Spacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(JarvisTheme.textPrimary)

                Text(message)
                    .font(JarvisTheme.Typography.metadata)
                    .foregroundStyle(JarvisTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tone.tint)
                        .buttonStyle(.plain)
                        .padding(.top, JarvisTheme.Spacing.xxs)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(JarvisTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.fill, in: .rect(cornerRadius: JarvisTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: JarvisTheme.Radius.control)
                .stroke(tone.border, lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
    }
}

struct JarvisEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        systemImage: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: JarvisTheme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(JarvisTheme.accent)
                .frame(width: 52, height: 52)
                .background(JarvisTheme.accentSoft.opacity(0.22), in: .circle)

            Text(title)
                .font(.headline)
                .foregroundStyle(JarvisTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(JarvisTheme.Typography.metadata)
                .foregroundStyle(JarvisTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(JarvisTheme.accent)
                    .controlSize(.small)
                    .padding(.top, JarvisTheme.Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, JarvisTheme.Spacing.xl)
        .padding(.vertical, JarvisTheme.Spacing.xxl)
        .background(JarvisTheme.surface.opacity(0.55), in: .rect(cornerRadius: JarvisTheme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: JarvisTheme.Radius.card)
                .stroke(JarvisTheme.border, lineWidth: 0.5)
        }
    }
}

struct JarvisHistorySkeleton: View {
    var rows: Int = 3

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { index in
                HStack(spacing: JarvisTheme.Spacing.sm) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(JarvisTheme.surfaceElevated)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(JarvisTheme.surfaceElevated)
                            .frame(width: index == 1 ? 178 : 218, height: 14)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(JarvisTheme.surface)
                            .frame(width: 142, height: 11)
                    }

                    Spacer()

                    RoundedRectangle(cornerRadius: 4)
                        .fill(JarvisTheme.surface)
                        .frame(width: 50, height: 11)
                }
                .padding(.vertical, JarvisTheme.Spacing.md)

                Rectangle()
                    .fill(JarvisTheme.divider)
                    .frame(height: 1)
                    .padding(.leading, 36)
            }
        }
        .redacted(reason: .placeholder)
        .opacity(0.85)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading conversations")
    }
}

struct JarvisConversationSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: JarvisTheme.Spacing.lg) {
            Spacer(minLength: 0)
            ForEach(0..<2, id: \.self) { index in
                HStack(alignment: .top, spacing: JarvisTheme.Spacing.sm) {
                    Circle()
                        .fill(JarvisTheme.surfaceElevated)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(JarvisTheme.surfaceElevated)
                            .frame(maxWidth: index == 0 ? 240 : 180, minHeight: 14)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(JarvisTheme.surface)
                            .frame(maxWidth: index == 0 ? 190 : 130, minHeight: 14)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .redacted(reason: .placeholder)
        .opacity(0.85)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading conversation history")
    }
}

struct JarvisActivityIndicator: View {
    let label: String
    let detail: String?
    let systemImage: String

    init(label: String, detail: String? = nil, systemImage: String = "sparkles") {
        self.label = label
        self.detail = detail
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: JarvisTheme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(JarvisTheme.accentSoft.opacity(0.28))
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(JarvisTheme.accent)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(JarvisTheme.textSecondary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(JarvisTheme.textTertiary)
                }
            }

            JarvisBouncingDots()
        }
        .accessibilityElement(children: .combine)
    }
}

struct JarvisBouncingProgressLabel: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(JarvisTheme.accent)
                    .frame(width: 3.5, height: 3.5)
                    .modifier(JarvisDotPulse(delay: Double(index) * 0.12))
            }
        }
        .accessibilityLabel("In progress")
    }
}

private struct JarvisDotPulse: ViewModifier {
    let delay: Double
    @State private var isRaised = false

    func body(content: Content) -> some View {
        content
            .offset(y: isRaised ? -1.5 : 1.5)
            .animation(
                .easeInOut(duration: 0.45)
                    .repeatForever()
                    .delay(delay),
                value: isRaised
            )
            .onAppear { isRaised = true }
    }
}

private struct JarvisBouncingDots: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(JarvisTheme.textTertiary)
                    .frame(width: 4, height: 4)
                    .offset(y: isAnimating ? -2 : 2)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever()
                            .delay(Double(index) * 0.12),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
    }
}
