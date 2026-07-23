//
//  HapticManager.swift
//  JARVIS
//

import UIKit

public enum HapticKind {
    case light, medium, success, warning, error, soft
}

@MainActor
public enum HapticManager {
    public static func play(_ kind: HapticKind) {
        switch kind {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .soft:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }
}
