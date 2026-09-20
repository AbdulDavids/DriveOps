//
//  BackgroundPollController.swift
//  DriveOps
//
//  iOS suspends a plain polling Task shortly after backgrounding —
//  `bluetooth-central` in Info.plist keeps CoreBluetooth *events* (writes,
//  notify callbacks) able to run, but does not itself keep an arbitrary
//  write-then-await-response loop scheduled indefinitely. This is why the
//  Live Activity previously froze on stale numbers as soon as the app was
//  backgrounded or the phone locked: the poll loop actually stopped
//  running, it wasn't a LiveActivityController bug.
//
//  There is no way to get full-rate (near-continuous) background polling
//  reliably; UIApplication.beginBackgroundTask only buys a limited grant
//  (historically ~30s, renewable, until the OS finally revokes it for this
//  launch). This is a best-effort extension, not a guarantee: it slows the
//  poll cadence while backgrounded so the limited time budget covers more
//  wall-clock time, and requests a fresh background task on each
//  background/foreground transition.
//

import Foundation
import UIKit

@MainActor
final class BackgroundPollController {
    static let shared = BackgroundPollController()

    /// While the app is active/foreground, OBDViewModel already polls as
    /// fast as each request/response round-trip allows. This is only the
    /// extra artificial delay added between cycles while backgrounded, to
    /// stretch the limited background-task time budget further.
    static let backgroundPollInterval: TimeInterval = 5.0

    private(set) var isBackgrounded = false
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var observers: [NSObjectProtocol] = []

    private init() {}

    func start() {
        guard observers.isEmpty else { return }
        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
            ) { _ in
                // queue: .main guarantees main-thread execution at runtime,
                // but this closure isn't statically @MainActor-isolated, so
                // hop explicitly to call into this actor-isolated singleton
                // (captured fresh here, not carried across the boundary as a
                // captured `weak self` from an outer non-isolated closure).
                Task { @MainActor in BackgroundPollController.shared.handleDidEnterBackground() }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { _ in
                Task { @MainActor in BackgroundPollController.shared.handleWillEnterForeground() }
            }
        )
    }

    private func handleDidEnterBackground() {
        isBackgrounded = true
        beginBackgroundTask()
    }

    private func handleWillEnterForeground() {
        isBackgrounded = false
        endBackgroundTask()
    }

    private func beginBackgroundTask() {
        endBackgroundTask()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "DriveOps.LivePoll") {
            // Expiration handler: the OS is about to force-kill remaining
            // background time. Nothing left to salvage — the poll loop
            // itself checks isBackgrounded/Task.isCancelled and will stop
            // gracefully on its own once suspended. Apple's docs don't
            // guarantee this runs on the main actor, so hop explicitly
            // rather than calling actor-isolated state from here directly.
            Task { @MainActor in BackgroundPollController.shared.endBackgroundTask() }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
