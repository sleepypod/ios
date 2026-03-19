import Foundation
import UserNotifications
import Observation

/// Bridges pod WebSocket events to local notifications and external webhooks.
/// The pod stays offline — iOS relays alerts to Slack/Discord.
@MainActor
@Observable
final class NotificationRelay {
    var isEnabled = true
    var webhookURL: String {
        get { UserDefaults.standard.string(forKey: "notificationWebhookURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "notificationWebhookURL") }
    }
    var enabledCategories: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: "notificationCategories") ?? ["adaptive", "alarm", "water", "system"])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: "notificationCategories")
        }
    }
    var recentNotifications: [RelayedNotification] = []

    struct RelayedNotification: Identifiable, Sendable {
        let id = UUID()
        let timestamp: Date
        let category: String
        let title: String
        let message: String
        let relayedToWebhook: Bool
    }

    // MARK: - Setup

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Handle Events

    /// Called when a notification-worthy event occurs (from WebSocket or internal).
    func relay(category: String, title: String, message: String, data: [String: Any] = [:]) async {
        guard isEnabled, enabledCategories.contains(category) else { return }

        // Local notification
        await sendLocalNotification(title: title, body: message, category: category)

        // Webhook
        var webhookSent = false
        if !webhookURL.isEmpty {
            webhookSent = await sendWebhook(title: title, message: message, category: category, data: data)
        }

        // Track
        let notification = RelayedNotification(
            timestamp: .now,
            category: category,
            title: title,
            message: message,
            relayedToWebhook: webhookSent
        )
        recentNotifications.insert(notification, at: 0)
        if recentNotifications.count > 50 { recentNotifications.removeLast() }
    }

    // MARK: - Adaptive Engine Events

    /// Relay an adaptive temperature change (from shadow or live mode)
    func relayAdaptiveChange(side: String, fromTemp: Int, toTemp: Int, reason: String, mode: String) async {
        let title = mode == "live" ? "Temperature Adjusted" : "Shadow: Would Adjust"
        let message = "\(side.capitalized) side: \(fromTemp)°F → \(toTemp)°F (\(reason))"
        await relay(category: "adaptive", title: title, message: message, data: [
            "side": side, "from_temp": fromTemp, "to_temp": toTemp, "reason": reason, "mode": mode
        ])
    }

    // MARK: - Local Notifications

    private func sendLocalNotification(title: String, body: String, category: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = category == "alarm" ? .defaultCritical : .default
        content.categoryIdentifier = "sleepypod.\(category)"

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Webhook

    private func sendWebhook(title: String, message: String, category: String, data: [String: Any]) async -> Bool {
        guard let url = URL(string: webhookURL) else { return false }

        // Support both Slack and Discord formats
        let isSlack = webhookURL.contains("hooks.slack.com")
        let isDiscord = webhookURL.contains("discord.com/api/webhooks")

        var payload: [String: Any]
        if isSlack {
            payload = [
                "text": "*\(title)*\n\(message)",
                "username": "Sleepypod",
                "icon_emoji": ":sleeping:"
            ]
        } else if isDiscord {
            payload = [
                "content": "**\(title)**\n\(message)",
                "username": "Sleepypod"
            ]
        } else {
            // Generic webhook
            payload = [
                "title": title,
                "message": message,
                "category": category,
                "timestamp": ISO8601DateFormatter().string(from: .now),
                "data": data
            ]
        }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            Log.general.error("Webhook failed: \(error)")
            return false
        }
    }
}
