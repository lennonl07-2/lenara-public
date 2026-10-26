import SwiftUI
import UserNotifications
import AVFoundation

struct ReminderNotificationRoute: Identifiable {
    let id = UUID()
    let reminderID: UUID
    let deliveredAt: Date
    var isDelivery = false
}

@MainActor
final class ReminderNotificationRouter: ObservableObject {
    static let shared = ReminderNotificationRouter()
    @Published var route: ReminderNotificationRoute?

    static func reminderID(from identifier: String, userInfo: [AnyHashable: Any]) -> UUID? {
        if let raw = userInfo["reminderID"] as? String, let id = UUID(uuidString: raw) { return id }
        guard identifier.hasPrefix("lenara_reminder_") else { return nil }
        return UUID(uuidString: String(identifier.dropFirst("lenara_reminder_".count).prefix(36)))
    }

    func receive(_ notification: UNNotification) {
        guard let id = Self.reminderID(from: notification.request.identifier, userInfo: notification.request.content.userInfo) else { return }
        let next = ReminderNotificationRoute(reminderID: id, deliveredAt: notification.date, isDelivery: true)
        // UIKit dismisses an editor/chat before the root presents the notification detail.
        // Keep the route in memory until SwiftData and onboarding have loaded on a cold launch.
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        if window?.rootViewController?.presentedViewController != nil {
            window?.rootViewController?.dismiss(animated: false) { self.route = next }
        } else { route = next }
    }
}

@MainActor
final class StrongAlarmPlayer {
    static let shared = StrongAlarmPlayer()
    private var player: AVAudioPlayer?
    private(set) var reminderID: UUID?

    func start(for id: UUID) throws {
        guard reminderID != id || player?.isPlaying != true else { return }
        guard let url = Bundle.main.url(forResource: "Alarma-Fuerte_MasDUR", withExtension: "wav") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        let audio = try AVAudioPlayer(contentsOf: url)
        audio.numberOfLoops = -1
        audio.prepareToPlay()
        guard audio.play() else { throw CocoaError(.fileReadUnknown) }
        player = audio
        reminderID = id
    }

    func stop() {
        player?.stop()
        player = nil
        reminderID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
