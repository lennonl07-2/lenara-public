import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

// MARK: - App Delegate
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        _ = LocalNotificationManager.shared
        let open = UNNotificationAction(identifier: "OPEN", title: "Ver / Posponer", options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([UNNotificationCategory(identifier: "LENARA_REMINDER", actions: [open], intentIdentifiers: [])])
        UserDefaults.standard.removeObject(forKey: "lenara.widgetCaptureRequested")
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: ReminderCaptureControlState.kind)
        }

        return true
    }

    // MARK: - Deep Link Handling (for Revyl auth bypass)
    func application(_ application: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Handle dev-login deep link for E2E testing
        // Format: lenara://dev-login?token=<E2E_LOGIN_TOKEN>
        guard url.host == "dev-login",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
            return false
        }

        // Store token for session bypass
        UserDefaults.standard.set(token, forKey: "lenara.e2eLoginToken")
        NotificationCenter.default.post(name: NSNotification.Name("LenaraE2ELoginReceived"), object: nil, userInfo: ["token": token])

        return true
    }

}
