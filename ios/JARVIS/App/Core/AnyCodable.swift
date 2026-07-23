//
//  AnyCodable.swift
//  JARVIS
//
//  A tiny dynamic-JSON wrapper for tool args/results whose schema is tool-specific.
//  ~40 lines; mirrors Apple's AnyEncodable pattern.
//

import Foundation

// Values are created from decoded JSON and treated as immutable transport
// payloads throughout the app. The erased `Any` storage prevents the compiler
// from proving Sendable conformance, so this boundary is explicitly audited.
public struct AnyCodable: Codable, Hashable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self.value = NSNull()
        } else if let b = try? c.decode(Bool.self) {
            self.value = b
        } else if let i = try? c.decode(Int.self) {
            self.value = i
        } else if let d = try? c.decode(Double.self) {
            self.value = d
        } else if let s = try? c.decode(String.self) {
            self.value = s
        } else if let arr = try? c.decode([AnyCodable].self) {
            self.value = arr.map { $0.value }
        } else if let dict = try? c.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            self.value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try c.encodeNil()
        case let b as Bool:
            try c.encode(b)
        case let i as Int:
            try c.encode(i)
        case let d as Double:
            try c.encode(d)
        case let s as String:
            try c.encode(s)
        case let arr as [Any]:
            try c.encode(arr.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try c.encode(dict.mapValues { AnyCodable($0) })
        default:
            try c.encodeNil()
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        // Best-effort JSON-based equality; avoids NSObject identity traps.
        let l = try? JSONSerialization.data(withJSONObject: lhs.value, options: [.fragmentsAllowed])
        let r = try? JSONSerialization.data(withJSONObject: rhs.value, options: [.fragmentsAllowed])
        return l == r
    }

    public func hash(into hasher: inout Hasher) {
        if let d = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) {
            hasher.combine(d)
        } else {
            hasher.combine(String(describing: value))
        }
    }

    public var stringified: String {
        if value is NSNull { return "" }
        if let s = value as? String { return s }
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    public var preview: String {
        let s = stringified.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count <= 200 { return s }
        return String(s.prefix(200)) + "…"
    }
}
