//
//  HermesStateViews.swift
//  Hermes
//
//  Reusable state surfaces for loading, empty, connection, and live-work
//  states. These keep transient product state visible without relying on
//  temporary toast-style overlays.
//

import SwiftUI

enum HermesStateTone {
    case neutral
    case info
    case success
    case warning
    case error

    var tint: Color {
        switch self {
        case .neutral: return HermesTheme.textSecondary
        case .info: return HermesTheme.accent
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    var fill: Color {
        switch self {
        case .neutral: return HermesTheme.surface
        case .info: return HermesTheme.accentSoft.opacity(0.20)
        case .success: return Color.green.opacity(0.12)
        case .warning: return Color.orange.opacity(0.13)
        case .error: return Color.red.opacity(0.13)
        }
    }

    var border: Color {
        switch self {
        case .neutral: return HermesTheme.border
        case .info: return HermesTheme.accent.opacity(0.25)
        case .success: return Color.green.opacity(0.25)
        case .warning: return Color.orange.opacity(0.28)
        case .error: return Color.red.opacity(0.28)
        }
    }
}

struct HermesStateBanner: View {
    let title: String
    let message: String
    let systemImage: String
    let tone: HermesStateTone
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        title: String,
        message: String,
        systemImage: String,
        tone: HermesStateTone = .neutral,
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
        HStack(alignment: .top, spacing: HermesTheme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tone.tint)
                .frame(width: 24, height: 24)
                .background(tone.tint.opacity(0.14), in: .circle)

            VStack(alignment: .leading, spacing: HermesTheme.Spacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HermesTheme.textPrimary)

                Text(message)
                    .font(HermesTheme.Typography.metadata)
                    .foregroundStyle(HermesTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tone.tint)
                        .buttonStyle(.plain)
                        .padding(.top, HermesTheme.Spacing.xxs)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(HermesTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.fill, in: .rect(cornerRadius: HermesTheme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.Radius.control)
                .stroke(tone.border, lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
    }
}

struct HermesEmptyState: View {
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
        VStack(spacing: HermesTheme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(HermesTheme.accent)
                .frame(width: 52, height: 52)
                .background(HermesTheme.accentSoft.opacity(0.22), in: .circle)

            Text(title)
                .font(.headline)
                .foregroundStyle(HermesTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(HermesTheme.Typography.metadata)
                .foregroundStyle(HermesTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(HermesTheme.accent)
                    .controlSize(.small)
                    .padding(.top, HermesTheme.Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, HermesTheme.Spacing.xl)
        .padding(.vertical, HermesTheme.Spacing.xxl)
        .background(HermesTheme.surface.opacity(0.55), in: .rect(cornerRadius: HermesTheme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.Radius.card)
                .stroke(HermesTheme.border, lineWidth: 0.5)
        }
    }
}

struct HermesHistorySkeleton: View {
    var rows: Int = 3

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { index in
                HStack(spacing: HermesTheme.Spacing.sm) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(HermesTheme.surfaceElevated)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(HermesTheme.surfaceElevated)
                            .frame(width: index == 1 ? 178 : 218, height: 14)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(HermesTheme.surface)
                            .frame(width: 142, height: 11)
                    }

                    Spacer()

                    RoundedRectangle(cornerRadius: 4)
                        .fill(HermesTheme.surface)
                        .frame(width: 50, height: 11)
                }
                .padding(.vertical, HermesTheme.Spacing.md)

                Rectangle()
                    .fill(HermesTheme.divider)
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

struct HermesConversationSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: HermesTheme.Spacing.lg) {
            Spacer(minLength: 0)
            ForEach(0..<2, id: \.self) { index in
                HStack(alignment: .top, spacing: HermesTheme.Spacing.sm) {
                    Circle()
                        .fill(HermesTheme.surfaceElevated)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(HermesTheme.surfaceElevated)
                            .frame(maxWidth: index == 0 ? 240 : 180, minHeight: 14)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(HermesTheme.surface)
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

struct HermesActivityIndicator: View {
    let label: String
    let detail: String?
    let systemImage: String

    init(label: String, detail: String? = nil, systemImage: String = "sparkles") {
        self.label = label
        self.detail = detail
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: HermesTheme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(HermesTheme.accentSoft.opacity(0.28))
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HermesTheme.accent)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HermesTheme.textSecondary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(HermesTheme.textTertiary)
                }
            }

            HermesBouncingDots()
        }
        .accessibilityElement(children: .combine)
    }
}

struct HermesBouncingProgressLabel: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(HermesTheme.accent)
                    .frame(width: 3.5, height: 3.5)
                    .modifier(HermesDotPulse(delay: Double(index) * 0.12))
            }
        }
        .accessibilityLabel("In progress")
    }
}

private struct HermesDotPulse: ViewModifier {
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

private struct HermesBouncingDots: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(HermesTheme.textTertiary)
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
