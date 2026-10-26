import Foundation
import UserNotifications

// MARK: - Local Notification Manager (Singleton)
class LocalNotificationManager: NSObject, ObservableObject {
    static let shared = LocalNotificationManager()
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Request authorization
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("Notification authorization failed: \(error)")
            return false
        }
    }

    // Every occurrence carries its reminder identity, including recurring and snoozed alerts.
    @MainActor
    func scheduleReminder(_ reminder: Reminder) async throws {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = await requestAuthorization()
            settings = await center.notificationSettings()
        }
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            throw NotificationSchedulingError.permissionNotGranted
        }
        let base = "lenara_reminder_\(reminder.id.uuidString)"
        let content = notificationContent(for: reminder)
        var requests: [UNNotificationRequest] = []
        if reminder.repeats {
            for slot in reminder.scheduleSlots {
                guard slot.nextDate(after: .now) != nil else { throw NotificationSchedulingError.invalidSchedule }
                requests.append(UNNotificationRequest(identifier: base + "_" + slot.id, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: slot.components, repeats: true)))
            }
            guard !requests.isEmpty else { throw NotificationSchedulingError.invalidSchedule }
        } else if reminder.snoozedUntil == nil {
            guard reminder.date > .now else { throw NotificationSchedulingError.dateInPast }
            requests.append(UNNotificationRequest(identifier: base, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, reminder.date.timeIntervalSinceNow), repeats: false)))
        }
        // Snoozing adds one occurrence; it never changes the series or changes a strong sound to a normal sound.
        if let snooze = reminder.snoozedUntil, snooze > .now {
            requests.append(UNNotificationRequest(identifier: base + "_snooze", content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, snooze.timeIntervalSinceNow), repeats: false)))
        }
        guard !requests.isEmpty else { throw NotificationSchedulingError.dateInPast }
        try await replaceRequests(requests, base: base)
        reminder.notificationID = base
    }

    private func notificationContent(for reminder: Reminder) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let name = UserDefaults.standard.string(forKey: "lenara.userName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        content.title = notificationTitleText(name: name)
        content.body = notificationBody(for: reminder)
        content.userInfo = ["reminderID": reminder.id.uuidString, "strongAlarm": reminder.isStrongAlarm]
        content.categoryIdentifier = "LENARA_REMINDER"
        content.threadIdentifier = reminder.id.uuidString
        let savedSound = UserDefaults.standard.string(forKey: "lenara.notificationSound") ?? "default"
        if reminder.isStrongAlarm {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "Alarma-Fuerte_MasDUR.wav"))
        } else if savedSound == "silent" { content.sound = nil }
        else if NotificationSoundLibrary.sounds.contains(where: { $0.fileName == savedSound }) {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: savedSound))
        } else { content.sound = .default }
        return content
    }

    private func replaceRequests(_ requests: [UNNotificationRequest], base: String) async throws {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let old = pending.filter { $0.identifier == base || $0.identifier.hasPrefix(base + "_") }
        guard pending.count - old.count + requests.count <= 64 else { throw NotificationSchedulingError.pendingLimitReached }
        // Restore the complete previous set if any add fails; do not leave half a weekly schedule.
        center.removePendingNotificationRequests(withIdentifiers: old.map(\.identifier))
        do {
            for request in requests { try await center.add(request) }
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier))
            for request in old { try? await center.add(request) }
            throw error
        }
    }

    @MainActor
    func snooze(_ reminder: Reminder, minutes: Int) async throws {
        guard (1...1440).contains(minutes) else { throw NotificationSchedulingError.invalidSchedule }
        let date = Date.now.addingTimeInterval(Double(minutes) * 60)
        let base = "lenara_reminder_\(reminder.id.uuidString)"
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let request = UNNotificationRequest(identifier: base + "_snooze", content: notificationContent(for: reminder),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(minutes) * 60, repeats: false))
        let regular = reminder.repeats ? pending.filter { ($0.identifier == base || $0.identifier.hasPrefix(base + "_")) && !$0.identifier.hasSuffix("_snooze") } : []
        try await replaceRequests(regular + [request], base: base)
        reminder.snoozedUntil = date
        reminder.acknowledgedAt = .now
        reminder.isCompleted = false
        reminder.notificationID = base
        reminder.updatedAt = .now
        removeDelivered(reminder)
        if StrongAlarmPlayer.shared.reminderID == reminder.id { StrongAlarmPlayer.shared.stop() }
    }

    @MainActor
    func acknowledge(_ reminder: Reminder) {
        let base = "lenara_reminder_\(reminder.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [base + "_snooze"])
        if !reminder.repeats { cancelReminder(reminder); reminder.isCompleted = true }
        reminder.snoozedUntil = nil
        reminder.acknowledgedAt = .now
        reminder.updatedAt = .now
        removeDelivered(reminder)
        if StrongAlarmPlayer.shared.reminderID == reminder.id { StrongAlarmPlayer.shared.stop() }
    }

    func removeDelivered(_ reminder: Reminder) {
        let base = "lenara_reminder_\(reminder.id.uuidString)"
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notifications in
            center.removeDeliveredNotifications(withIdentifiers: notifications.map(\.request.identifier).filter { $0 == base || $0.hasPrefix(base + "_") })
        }
    }

    @MainActor
    func refreshScheduledReminderCopy(_ reminders: [Reminder]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        for reminder in reminders where !reminder.isCompleted {
            let base = "lenara_reminder_\(reminder.id.uuidString)"
            // A clean install or device restore can retain the database but lose iOS's queue.
            // Rebuild only future occurrences; never replay an expired reminder.
            var expected = Set(reminder.repeats ? reminder.scheduleSlots.map { base + "_" + $0.id } : [])
            if let snooze = reminder.snoozedUntil, snooze > .now { expected.insert(base + "_snooze") }
            else if !reminder.repeats && reminder.snoozedUntil == nil && reminder.date > .now { expected.insert(base) }
            let actual = Set(pending.map(\.identifier))
            if !expected.isSubset(of: actual) {
                do { try await scheduleReminder(reminder) }
                catch { print("Could not restore reminder notification: \(error.localizedDescription)") }
                continue
            }
            // Upgrade old payloads and remove the erroneous interval-repeat strong alarms.
            for request in pending where request.identifier == base || request.identifier.hasPrefix(base + "_") {
                if reminder.isStrongAlarm, request.trigger is UNTimeIntervalNotificationTrigger, request.trigger?.repeats == true {
                    center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                    if reminder.date > .now { try? await scheduleReminder(reminder) }
                    continue
                }
                var trigger = request.trigger
                if trigger is UNTimeIntervalNotificationTrigger, trigger?.repeats == false {
                    // Refreshing on foreground must not restart a relative countdown.
                    let deadline = request.identifier.hasSuffix("_snooze") ? reminder.snoozedUntil : reminder.date
                    guard let deadline, deadline > .now else { continue }
                    trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)
                }
                try? await center.add(UNNotificationRequest(identifier: request.identifier, content: notificationContent(for: reminder), trigger: trigger))
            }
        }
    }

    @MainActor
    func reschedulePendingRemindersWithSelectedSound(_ reminders: [Reminder]) async {
        await refreshScheduledReminderCopy(reminders)
    }

    private func notificationTitle(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // A spoken request such as “recuérdame ponerme bloqueador” is addressed to the user.
        return trimmed.replacingOccurrences(
            of: #"([aeiou]r)me\b"#,
            with: "$1te",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private func notificationTitleText(name: String) -> String {
        name.isEmpty ? "Hola" : "Hola, \(name)"
    }

    private func notificationBody(for reminder: Reminder) -> String {
        "Acuérdate de: \(notificationTitle(from: reminder.title))"
    }

    // MARK: - Cancel notification
    func cancelReminder(_ reminder: Reminder) {
        let id = reminder.id
        DispatchQueue.main.async {
            if StrongAlarmPlayer.shared.reminderID == id { StrongAlarmPlayer.shared.stop() }
        }
        let base = "lenara_reminder_\(reminder.id.uuidString)"
        let identifiers = [base, base + "_snooze"] + reminder.scheduleSlots.map { base + "_" + $0.id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        removeDelivered(reminder)
        reminder.notificationID = nil
    }

    // MARK: - Cancel all
    func cancelAll() {
        DispatchQueue.main.async { StrongAlarmPlayer.shared.stop() }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}

enum NotificationSchedulingError: LocalizedError {
    case permissionNotGranted
    case dateInPast
    case pendingLimitReached
    case invalidSchedule

    var errorDescription: String? {
        switch self {
        case .invalidSchedule: return "Revisa los días y las horas del recordatorio."
        case .permissionNotGranted: return "Las notificaciones están desactivadas. Actívalas en Ajustes de iOS para recibir este aviso."
        case .dateInPast: return "La fecha del recordatorio debe estar en el futuro."
        case .pendingLimitReached: return "iOS ya tiene 64 avisos de Lenara pendientes. Completa o elimina uno antes de programar otro."
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension LocalNotificationManager: UNUserNotificationCenterDelegate {
    // Explicit callbacks keep UIKit's response completion on the main thread. The async
    // Objective-C bridge on the connected iOS version completed on a cooperative worker,
    // triggering UIKit's state restoration assertion when a notification was tapped.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        DispatchQueue.main.async {
            if notification.request.content.userInfo["strongAlarm"] as? Bool == true {
                ReminderNotificationRouter.shared.receive(notification)
                completionHandler([.banner])
            } else { completionHandler([.banner, .sound]) }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            if response.actionIdentifier != UNNotificationDismissActionIdentifier {
                ReminderNotificationRouter.shared.receive(response.notification)
            }
            completionHandler()
        }
    }
}
