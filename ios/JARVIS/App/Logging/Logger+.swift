//
//  Logger+.swift
//  JARVIS
//
//  os.Logger wrappers for the JARVIS subsystems.
//

import Foundation
import os

public enum JarvisLog {
    public static let subsystem = "com.jarvis.mobile"

    public static let app     = Logger(subsystem: subsystem, category: "app")
    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let sse     = Logger(subsystem: subsystem, category: "sse")
    public static let render  = Logger(subsystem: subsystem, category: "render")
    public static let auth    = Logger(subsystem: subsystem, category: "auth")
    public static let store   = Logger(subsystem: subsystem, category: "store")
}
