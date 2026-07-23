//
//  KeychainStore.swift
//  JARVIS
//
//  Wrapper over KeychainAccess for the bridge URL, bearer token, profile, and APNs token.
//  Falls back to UserDefaults when the iOS Simulator's keychain is unavailable
//  (no signing identity → no application-identifier entitlement).
//

import Foundation
import KeychainAccess

public final class KeychainStore: @unchecked Sendable {
    public static let shared = KeychainStore()

    private let keychain: Keychain
    private let service = "com.hermes.mobile"
    private let useFallback: Bool
    private let defaults = UserDefaults(suiteName: "com.hermes.mobile.dev-store") ?? .standard

    public enum Key: String {
        case gatewayURL = "gatewayURL"
        case bearerToken = "bearerToken"
        case profile = "profile"
        case deviceToken = "deviceToken"
        case apnsTokenCached = "apnsTokenCached"
        case sessionID = "activeSessionID"
        case mockMode = "mockMode"
    }

    public init(service: String = "com.hermes.mobile") {
        self.keychain = Keychain(service: service)
            .accessibility(.afterFirstUnlockThisDeviceOnly)
            .synchronizable(false)

        // Sanity-test the keychain at startup so any entitlement/permission
        // problem surfaces in the log immediately instead of silently failing.
        var keychainOK = false
        do {
            try keychain.set("ok", key: "_keychain_smoketest")
            let readBack = try keychain.getString("_keychain_smoketest")
            try? keychain.remove("_keychain_smoketest")
            NSLog("[JARVIS][Keychain] smoketest readback=%@", readBack ?? "nil")
            keychainOK = (readBack == "ok")
        } catch {
            NSLog("[JARVIS][Keychain] smoketest FAILED — falling back to UserDefaults: %@", "\(error)")
        }
        self.useFallback = !keychainOK
        if useFallback {
            NSLog("[JARVIS][Keychain] WARNING: using UserDefaults fallback (no app-identifier entitlement). NOT for production.")
        }
    }

    private func _set(_ key: Key, _ value: String?) {
        if useFallback {
            defaults.set(value, forKey: "hc." + key.rawValue)
            return
        }
        do {
            if let v = value, !v.isEmpty {
                try keychain.set(v, key: key.rawValue)
            } else {
                try keychain.remove(key.rawValue)
            }
        } catch {
            NSLog("[JARVIS][Keychain] set %@ failed (using fallback): %@", key.rawValue, "\(error)")
            defaults.set(value, forKey: "hc." + key.rawValue)
        }
    }

    private func _get(_ key: Key) -> String? {
        if useFallback {
            return defaults.string(forKey: "hc." + key.rawValue)
        }
        do {
            return try keychain.getString(key.rawValue)
        } catch {
            NSLog("[JARVIS][Keychain] get %@ failed (using fallback): %@", key.rawValue, "\(error)")
            return defaults.string(forKey: "hc." + key.rawValue)
        }
    }

    // MARK: - Gateway URL

    public var gatewayURL: URL? {
        get {
            guard let s = _get(.gatewayURL), let url = URL(string: s) else { return nil }
            return url
        }
        set { _set(.gatewayURL, newValue?.absoluteString) }
    }

    // MARK: - Bearer token

    public var bearerToken: String? {
        get { _get(.bearerToken) }
        set { _set(.bearerToken, newValue) }
    }

    // MARK: - Profile

    public var profile: String? {
        get { _get(.profile) }
        set { _set(.profile, newValue) }
    }

    // MARK: - APNs device token

    public var deviceToken: String? {
        get { _get(.deviceToken) }
        set { _set(.deviceToken, newValue) }
    }

    public var apnsTokenCached: Bool {
        get { _get(.apnsTokenCached) == "1" }
        set { _set(.apnsTokenCached, newValue ? "1" : "0") }
    }

    public var sessionID: String? {
        get { _get(.sessionID) }
        set { _set(.sessionID, newValue) }
    }

    public var isMockMode: Bool {
        get { _get(.mockMode) == "1" }
        set { _set(.mockMode, newValue ? "1" : "0") }
    }

    // MARK: - Reset

    public func wipe() {
        for k in [Key.gatewayURL, .bearerToken, .profile, .deviceToken, .apnsTokenCached, .sessionID, .mockMode] {
            _set(k, nil)
        }
    }

    public var isConfigured: Bool {
        isMockMode || (gatewayURL != nil && bearerToken?.isEmpty == false)
    }
}
