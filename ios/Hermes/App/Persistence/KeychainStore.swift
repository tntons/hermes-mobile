//
//  KeychainStore.swift
//  Hermes
//
//  Wrapper over KeychainAccess for the bridge URL, bearer token, profile, and APNs token.
//

import Foundation
import KeychainAccess

public final class KeychainStore: @unchecked Sendable {
    public static let shared = KeychainStore()

    private let keychain: Keychain
    private let service = "com.hermes.mobile"

    public enum Key: String {
        case gatewayURL = "gatewayURL"
        case bearerToken = "bearerToken"
        case profile = "profile"
        case deviceToken = "deviceToken"
        case apnsTokenCached = "apnsTokenCached"
        case sessionID = "activeSessionID"
    }

    public init(service: String = "com.hermes.mobile") {
        self.keychain = Keychain(service: service)
            .accessibility(.afterFirstUnlockThisDeviceOnly)
            .synchronizable(false)
    }

    // MARK: - Gateway URL

    public var gatewayURL: URL? {
        get {
            guard let s = try? keychain.getString(Key.gatewayURL.rawValue),
                  let url = URL(string: s)
            else { return nil }
            return url
        }
        set {
            if let v = newValue?.absoluteString {
                try? keychain.set(v, key: Key.gatewayURL.rawValue)
            } else {
                try? keychain.remove(Key.gatewayURL.rawValue)
            }
        }
    }

    // MARK: - Bearer token

    public var bearerToken: String? {
        get { (try? keychain.getString(Key.bearerToken.rawValue)) ?? nil }
        set {
            if let v = newValue, !v.isEmpty {
                try? keychain.set(v, key: Key.bearerToken.rawValue)
            } else {
                try? keychain.remove(Key.bearerToken.rawValue)
            }
        }
    }

    // MARK: - Profile

    public var profile: String? {
        get { try? keychain.getString(Key.profile.rawValue) }
        set {
            if let v = newValue, !v.isEmpty {
                try? keychain.set(v, key: Key.profile.rawValue)
            } else {
                try? keychain.remove(Key.profile.rawValue)
            }
        }
    }

    // MARK: - APNs device token

    public var deviceToken: String? {
        get { try? keychain.getString(Key.deviceToken.rawValue) }
        set {
            if let v = newValue, !v.isEmpty {
                try? keychain.set(v, key: Key.deviceToken.rawValue)
            } else {
                try? keychain.remove(Key.deviceToken.rawValue)
            }
        }
    }

    public var apnsTokenCached: Bool {
        get { (try? keychain.getString(Key.apnsTokenCached.rawValue)) == "1" }
        set {
            try? keychain.set(newValue ? "1" : "0", key: Key.apnsTokenCached.rawValue)
        }
    }

    public var sessionID: String? {
        get { try? keychain.getString(Key.sessionID.rawValue) }
        set {
            if let v = newValue, !v.isEmpty {
                try? keychain.set(v, key: Key.sessionID.rawValue)
            } else {
                try? keychain.remove(Key.sessionID.rawValue)
            }
        }
    }

    // MARK: - Reset

    public func wipe() {
        for k in [Key.gatewayURL, .bearerToken, .profile, .deviceToken, .apnsTokenCached, .sessionID] {
            try? keychain.remove(k.rawValue)
        }
    }

    public var isConfigured: Bool {
        gatewayURL != nil && bearerToken?.isEmpty == false
    }
}
