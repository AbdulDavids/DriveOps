//
//  AppLogger.swift
//  DriveOps
//
//  Mirrors OBDViewModel.log() to the system console (Console.app / Xcode's
//  debug console) so a session can be inspected without the in-app Logs tab —
//  useful once you're off the simulator and away from a plugged-in debugger.
//

import os

enum AppLogger {
    static let connection = Logger(subsystem: "abduldavids.DriveOps", category: "connection")
    static let liveData = Logger(subsystem: "abduldavids.DriveOps", category: "liveData")
    static let diagnostics = Logger(subsystem: "abduldavids.DriveOps", category: "diagnostics")
    static let demo = Logger(subsystem: "abduldavids.DriveOps", category: "demo")
}
