//
//  JarvisAPI.swift
//  JARVIS
//
//  Centralizes URL construction for every endpoint we call.
//

import Foundation

public enum JarvisAPI {
    case health
    case sessions
    case session(id: String, messages: Bool)
    case newSession
    case renameSession
    case deleteSession
    case pinSession
    case archiveSession
    case chatStart
    case chatStream(streamID: String, afterEventID: String?)
    case chatStreamStatus(streamID: String)
    case chatCancel(streamID: String)
    case registerDevice

    public func url(base: URL) -> URL {
        var c = URLComponents()
        c.scheme = base.scheme
        c.host = base.host
        c.port = base.port
        switch self {
        case .health:
            c.path = "/health"
        case .sessions:
            c.path = "/api/sessions"
        case .session(let id, let messages):
            c.path = "/api/session"
            c.queryItems = [
                URLQueryItem(name: "session_id", value: id),
                URLQueryItem(name: "messages", value: messages ? "1" : "0"),
            ]
        case .newSession:
            c.path = "/api/session/new"
        case .renameSession:
            c.path = "/api/session/rename"
        case .deleteSession:
            c.path = "/api/session/delete"
        case .pinSession:
            c.path = "/api/session/pin"
        case .archiveSession:
            c.path = "/api/session/archive"
        case .chatStart:
            c.path = "/api/chat/start"
        case .chatStream(let sid, let after):
            c.path = "/api/chat/stream"
            var qi = [URLQueryItem(name: "stream_id", value: sid)]
            if let a = after { qi.append(URLQueryItem(name: "after_event_id", value: a)) }
            c.queryItems = qi
        case .chatStreamStatus(let sid):
            c.path = "/api/chat/stream/status"
            c.queryItems = [URLQueryItem(name: "stream_id", value: sid)]
        case .chatCancel(let sid):
            c.path = "/api/chat/cancel"
            c.queryItems = [URLQueryItem(name: "stream_id", value: sid)]
        case .registerDevice:
            c.path = "/mobile/device"
        }
        return c.url(relativeTo: base)!
    }

    public var method: String {
        switch self {
        case .health, .sessions, .session, .chatStream, .chatStreamStatus, .chatCancel:
            return "GET"
        case .newSession, .renameSession, .deleteSession, .pinSession, .archiveSession,
             .chatStart, .registerDevice:
            return "POST"
        }
    }

    public func urlRequest(base: URL, token: String, body: Data? = nil) -> URLRequest {
        let url = url(base: base)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body, !body.isEmpty {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 60
        return req
    }
}
