import Foundation
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    @Published private(set) var enabled = false

    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        enabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    func setEnabled(_ value: Bool) async {
        if value {
            do {
                enabled = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                enabled = false
            }
        } else {
            enabled = false
        }
    }
}
