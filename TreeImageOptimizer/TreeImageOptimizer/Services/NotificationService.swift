import Foundation
import UserNotifications

/// アプリ前面表示時にもバナーを出すためのデリゲート。
/// 設定しないとフォアグラウンド中の通知は抑制される。
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationCenterDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// 完了通知。
struct NotificationService: Sendable {
    func requestAuthorization() async -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// 変換完了を通知する。文言は呼び出し側Modelが `L10n` で解決して渡す。
    func notify(body: String) async {
        let content = UNMutableNotificationContent()
        content.title = "tree-image-optimizer"
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
