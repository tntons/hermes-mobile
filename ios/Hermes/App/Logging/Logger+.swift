//
//  Logger+.swift
//  Hermes
//
//  os.Logger wrappers for the Hermes subsystems.
//

import Foundation
import os

public enum HermesLog {
    public static let subsystem = "com.hermes.mobile"

    public static let app     = Logger(subsystem: subsystem, category: "app")
    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let sse     = Logger(subsystem: subsystem, category: "sse")
    public static let render  = Logger(subsystem: subsystem, category: "render")
    public static let auth    = Logger(subsystem: subsystem, category: "auth")
    public static let store   = Logger(subsystem: subsystem, category: "store")
}
