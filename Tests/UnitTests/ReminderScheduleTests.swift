import XCTest
import UserNotifications
@testable import Lenara

final class ReminderScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Lima")!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 10))! }
    private func parse(_ text: String) -> Intent { IntentParser(calendar: calendar).parse(text, now: now) }

    func testDailyMultipleTimes() {
        let intent = parse("Recuérdame tomar agua todos los días a las 9 am y a las 6 pm")
        XCTAssertEqual(intent.title, "tomar agua")
        XCTAssertEqual(Set(intent.recurrenceSlots), Set([ReminderSlot(hour: 9, minute: 0), ReminderSlot(hour: 18, minute: 0)]))
        XCTAssertNotNil(intent.date)
    }
    func testTuesdayMorningAfternoonNight() {
        let intent = parse("Recuérdame estirar todos los martes a las 9 de la mañana y a las 3 de la tarde y a las 9 de la noche")
        XCTAssertEqual(intent.title, "estirar")
        XCTAssertEqual(Set(intent.recurrenceSlots), Set([9, 15, 21].map { ReminderSlot(weekday: 3, hour: $0, minute: 0) }))
    }
    func testDifferentDaysKeepTheirOwnTimes() {
        let intent = parse("Recuérdame estudiar todos los lunes a las 5 pm, todos los martes a las 9 am y todos los domingos a las 20:00")
        XCTAssertEqual(intent.title, "estudiar")
        XCTAssertEqual(Set(intent.recurrenceSlots), Set([ReminderSlot(weekday: 2, hour: 17, minute: 0), ReminderSlot(weekday: 3, hour: 9, minute: 0), ReminderSlot(weekday: 1, hour: 20, minute: 0)]))
    }
    func testSharedWeekdaysAndMinutes() {
        let intent = parse("Avísame los lunes y miércoles a las seis y media de la tarde revisar el proyecto")
        XCTAssertEqual(intent.title, "revisar el proyecto")
        XCTAssertEqual(Set(intent.recurrenceSlots), Set([2, 4].map { ReminderSlot(weekday: $0, hour: 18, minute: 30) }))
    }
    func testWorkdays() {
        XCTAssertEqual(parse("Recuérdame salir de lunes a viernes a las 08:00").recurrenceSlots.count, 5)
    }
    func testWeekend() {
        XCTAssertEqual(Set(parse("Recuérdame limpiar los fines de semana a las 10:00").recurrenceSlots.compactMap(\.weekday)), Set([1, 7]))
    }
    func testAmbiguousOrInvalidScheduleNeverPartiallySchedules() {
        for phrase in ["todos los lunes a las 5", "todos los días a las 25:00", "todos los días a las 9 am y a las 3", "cada dos semanas a las 9 am", "todos los días a las 9 am hasta diciembre", "cada hora a las 9 am", "todos los meses a las 9 am", "cada lunes a jueves a las 9 am"] {
            let intent = parse("Recuérdame estudiar " + phrase)
            XCTAssertNil(intent.date, phrase)
            XCTAssertTrue(intent.recurrenceSlots.isEmpty, phrase)
            XCTAssertNotNil(intent.clarification, phrase)
        }
    }
    func testNoonMidnightAndDeduplication() {
        let intent = parse("Recuérdame tomar agua todos los días al mediodía y a medianoche")
        XCTAssertEqual(Set(intent.recurrenceSlots.map(\.hour)), Set([0, 12]))
        XCTAssertEqual(parse("Recuérdame salir todos los días a las 9 am y a las 9 am").recurrenceSlots.count, 1)
    }
    func testWeeklyNextOccurrenceIsFutureAndCorrectDay() throws {
        let intent = parse("Recuérdame llamar todos los domingos a las 9 am")
        let date = try XCTUnwrap(intent.date)
        XCTAssertEqual(calendar.component(.day, from: date), 25)
        XCTAssertEqual(calendar.component(.hour, from: date), 9)
    }
    @MainActor
    func testRoutingSupportsOldAndSnoozedNotifications() {
        let id = UUID()
        for suffix in ["", "_snooze", "_3-9-0"] {
            XCTAssertEqual(ReminderNotificationRouter.reminderID(from: "lenara_reminder_" + id.uuidString + suffix, userInfo: [:]), id)
        }
        XCTAssertNil(ReminderNotificationRouter.reminderID(from: "invalid", userInfo: [:]))
    }
    func testLegacyDailyReminderRetainsSchedule() {
        let reminder = Reminder(title: "Agua", date: now, repeats: true)
        XCTAssertEqual(reminder.scheduleSlots.count, 1)
        XCTAssertNil(reminder.scheduleSlots.first?.weekday)
        let slots = [ReminderSlot(weekday: 2, hour: 17, minute: 0), ReminderSlot(weekday: 3, hour: 9, minute: 0)]
        reminder.scheduleSlots = slots
        XCTAssertEqual(reminder.scheduleSlots, slots)
        XCTAssertTrue(reminder.repeats)
    }
    func testSnoozedStrongAlarmDoesNotAppearActiveBeforeItsTime() {
        let reminder = Reminder(title: "Salir", date: now.addingTimeInterval(-60), isStrongAlarm: true)
        reminder.snoozedUntil = now.addingTimeInterval(600)
        XCTAssertFalse(reminder.hasUnacknowledgedStrongOccurrence(at: now))
        XCTAssertTrue(reminder.hasUnacknowledgedStrongOccurrence(at: now.addingTimeInterval(601)))
        reminder.acknowledgedAt = now.addingTimeInterval(602)
        XCTAssertFalse(reminder.hasUnacknowledgedStrongOccurrence(at: now.addingTimeInterval(603)))
    }
    @MainActor
    func testDeviceSchedulesWeeklySlotsAndSnoozeWithoutChangingSeries() async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional].contains(settings.authorizationStatus) else { throw XCTSkip("Notification permission required") }
        let reminder = Reminder(title: "Validación Lenara — recurrencia", date: .now.addingTimeInterval(3600), repeats: true, isStrongAlarm: true)
        reminder.scheduleSlots = [ReminderSlot(weekday: 2, hour: 17, minute: 0), ReminderSlot(weekday: 3, hour: 9, minute: 0)]
        defer { LocalNotificationManager.shared.cancelReminder(reminder) }
        try await LocalNotificationManager.shared.scheduleReminder(reminder)
        let base = "lenara_reminder_" + reminder.id.uuidString
        var requests = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(base) }
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertEqual(request.content.userInfo["reminderID"] as? String, reminder.id.uuidString)
            XCTAssertTrue(request.trigger is UNCalendarNotificationTrigger)
            XCTAssertEqual(request.trigger?.repeats, true)
        }
        try await LocalNotificationManager.shared.snooze(reminder, minutes: 30)
        requests = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(base) }
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests.first(where: { $0.identifier.hasSuffix("_snooze") })?.content.userInfo["strongAlarm"] as? Bool, true)
        LocalNotificationManager.shared.acknowledge(reminder)
        requests = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(base) }
        XCTAssertEqual(requests.count, 2)
        XCTAssertFalse(reminder.isCompleted)
    }
    @MainActor
    func testOneOffStrongAlarmDoesNotRepeatAtWrongInterval() async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional].contains(settings.authorizationStatus) else { throw XCTSkip("Notification permission required") }
        let reminder = Reminder(title: "Validación Lenara — sonido", date: .now.addingTimeInterval(3600), isStrongAlarm: true)
        defer { LocalNotificationManager.shared.cancelReminder(reminder) }
        try await LocalNotificationManager.shared.scheduleReminder(reminder)
        let requests = await center.pendingNotificationRequests()
        let request = try XCTUnwrap(requests.first { $0.identifier == reminder.notificationID })
        XCTAssertEqual(request.trigger?.repeats, false)
        XCTAssertNotNil(request.content.sound)
        LocalNotificationManager.shared.acknowledge(reminder)
        XCTAssertTrue(reminder.isCompleted)
    }

    func testOneOffClockNotationAndStrongAlarmCommand() throws {
        let oneOff = parse("Recuérdame salir hoy a las 18:30")
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(oneOff.date)), 18)
        let strong = parse("Pon una alarma fuerte para apagar el horno dentro de diez minutos")
        XCTAssertEqual(strong.action, .createReminder)
        XCTAssertEqual(strong.title, "apagar el horno")
        XCTAssertTrue(strong.isStrongAlarm)
        XCTAssertEqual(try XCTUnwrap(strong.date).timeIntervalSince(now), 600, accuracy: 0.1)
    }
    func testRecurrencePreservesAccentsInAction() {
        XCTAssertEqual(parse("Recuérdame llamar a mamá todos los miércoles a las 9 am").title, "llamar a mamá")
    }
    @MainActor
    func testQuotaFailureKeepsExistingRequests() async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional].contains(settings.authorizationStatus) else { throw XCTSkip("Notification permission required") }
        let reminder = Reminder(title: "Validación Lenara — límite", date: .now.addingTimeInterval(3600), repeats: true)
        let original = [ReminderSlot(weekday: 2, hour: 17, minute: 0)]
        reminder.scheduleSlots = original
        defer { reminder.scheduleSlots = original; LocalNotificationManager.shared.cancelReminder(reminder) }
        try await LocalNotificationManager.shared.scheduleReminder(reminder)
        reminder.scheduleSlots = (0..<65).map { ReminderSlot(weekday: 1 + $0 / 24, hour: $0 % 24, minute: 0) }
        do {
            try await LocalNotificationManager.shared.scheduleReminder(reminder)
            XCTFail("A schedule above the iOS quota must fail")
        } catch NotificationSchedulingError.pendingLimitReached {} catch { XCTFail("Unexpected error: \(error)") }
        let remaining = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("lenara_reminder_" + reminder.id.uuidString) }
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual((remaining.first?.trigger as? UNCalendarNotificationTrigger)?.dateComponents.weekday, 2)
    }

    @MainActor
    func testRestoringMissingQueuePreservesSnoozeAndWeeklySchedule() async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional].contains(settings.authorizationStatus) else { throw XCTSkip("Notification permission required") }
        let snoozed = Reminder(title: "Validación de restauración", date: .now.addingTimeInterval(-600), isStrongAlarm: true)
        snoozed.snoozedUntil = .now.addingTimeInterval(3600)
        let weekly = Reminder(title: "Validación semanal restaurada", date: .now.addingTimeInterval(-600), repeats: true)
        weekly.scheduleSlots = [ReminderSlot(weekday: 2, hour: 9, minute: 0), ReminderSlot(weekday: 6, hour: 18, minute: 0)]
        defer {
            LocalNotificationManager.shared.cancelReminder(snoozed)
            LocalNotificationManager.shared.cancelReminder(weekly)
        }
        await LocalNotificationManager.shared.refreshScheduledReminderCopy([snoozed, weekly])
        let pending = await center.pendingNotificationRequests()
        let snoozes = pending.filter { $0.identifier.hasPrefix("lenara_reminder_" + snoozed.id.uuidString) }
        XCTAssertEqual(snoozes.count, 1)
        XCTAssertTrue(snoozes.first?.identifier.hasSuffix("_snooze") == true)
        XCTAssertEqual(snoozes.first?.content.userInfo["strongAlarm"] as? Bool, true)
        XCTAssertEqual(pending.filter { $0.identifier.hasPrefix("lenara_reminder_" + weekly.id.uuidString) }.count, 2)
    }

}
