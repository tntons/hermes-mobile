//
//  APIError.swift
//  Hermes
//

import Foundation

public enum APIError: LocalizedError, Sendable {
    case notConfigured
    case http(status: Int, body: String)
    case decode(String)
    case transport(String)
    case unauthorized
    case offline
    case upstream(message: String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Not connected to a Hermes gateway. Open Settings to configure."
        case .http(let s, _): return "Server returned HTTP \(s)."
        case .decode(let s): return "Could not decode response: \(s)"
        case .transport(let s): return "Network error: \(s)"
        case .unauthorized: return "Access token rejected. Re-enter your access token in Settings."
        case .offline: return "You appear to be offline."
        case .upstream(let s): return "Server: \(s)"
        }
    }
}
