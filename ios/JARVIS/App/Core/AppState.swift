//
//  AppState.swift
//  JARVIS
//
//  Single observable root state. Holds: auth state, scene phase, network reachability,
//  and (Phase 6) the list of in-flight stream cursors to resume on foreground.
//

import Foundation
import Network
import Observation
import SwiftUI

@MainActor
public enum AuthState: Equatable {
    case unconfigured
    case configured
    case misconfigured(reason: String)
}

@MainActor
public enum Reachability: Equatable {
    case unknown
    case online
    case offline
}

@Observable
@MainActor
public final class AppState {
    public var authState: AuthState
    public var scenePhase: ScenePhase = .active
    public var reachability: Reachability = .unknown
    public var pendingStreamIDs: [String] = []

    private let pathMonitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.jarvis.mobile.network", qos: .utility)

    public init() {
        if KeychainStore.shared.isConfigured {
            self.authState = .configured
        } else {
            self.authState = .unconfigured
        }
        self.pathMonitor = NWPathMonitor()

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let status: Reachability = (path.status == .satisfied) ? .online : .offline
            Task { @MainActor [weak self] in
                self?.reachability = status
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    public func reloadAuth() {
        if KeychainStore.shared.isConfigured {
            authState = .configured
        } else {
            authState = .unconfigured
        }
    }

    public func setMisconfigured(_ reason: String) {
        authState = .misconfigured(reason: reason)
    }
}
