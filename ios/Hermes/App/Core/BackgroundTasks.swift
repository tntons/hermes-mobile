//
//  BackgroundTasks.swift
//  Hermes
//
//  BGAppRefreshTask ONLY for opportunistic session-list refreshes. We
//  intentionally NEVER try to keep the SSE stream alive while the app is
//  backgrounded — iOS will eventually drop the socket, and the server-side
//  worker + run journal handle that gracefully on the next foreground.
//

import BackgroundTasks
import Foundation

@MainActor
public enum HermesBackgroundTasks {
    public static let refreshIdentifier = "com.hermes.mobile.refresh"

    public static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: nil) { task in
            handleRefresh(task: task as! BGAppRefreshTask)
        }
    }

    public static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)   // 30 min
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            HermesLog.app.warning("BGAppRefresh schedule failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func handleRefresh(task: BGAppRefreshTask) {
        scheduleRefresh()
        task.expirationHandler = { task.setTaskCompleted(success: false) }

        let worker = Task { @MainActor in
            guard KeychainStore.shared.isConfigured else {
                task.setTaskCompleted(success: false); return
            }
            // Refresh session list (cheapest JSON call).
            let url = KeychainStore.shared.gatewayURL!
            let token = KeychainStore.shared.bearerToken!
            let client = HermesClient(config: .init(gatewayURL: url, bearerToken: token))
            do {
                let list = try await client.fetchSessions()
                HermesDAO.upsert(list)
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = { _ in worker.cancel() }
    }
}
