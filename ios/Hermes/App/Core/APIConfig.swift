//
//  APIConfig.swift
//  Hermes
//
//  Reads gateway URL + bearer token from the Keychain. Source of truth for the
//  HermesClient. Stays purely synchronous and safe to call from any context.
//

import Foundation
import Observation

@Observable
@MainActor
public final class APIConfig {
    public private(set) var gatewayURL: URL?
    public private(set) var bearerToken: String?
    public private(set) var isMock: Bool = false

    public init() {
        reload()
    }

    public func reload() {
        let kc = KeychainStore.shared
        gatewayURL = kc.gatewayURL
        bearerToken = kc.bearerToken
        isMock = kc.isMockMode
    }

    public var isConfigured: Bool {
        isMock || (gatewayURL != nil && (bearerToken?.isEmpty == false))
    }
}
