import Foundation
import SwiftData

enum VoiceReminderError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

struct VoiceReminderService {
    // A named command avoids accidentally sending “recuérdame enviar un correo…”.
    static func requestBeforeSendCommand(_ transcript: String) -> String? {
        guard let command = transcript.range(of: #"\blenara[\s,;:]+enviar[\s.!?]*$"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let request = String(transcript[..<command.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return request.isEmpty ? nil : request
    }

    static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) throws -> Intent {
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { throw VoiceReminderError.invalid("No te escuché. Vuelve a dictar el recordatorio.") }
        let parser = IntentParser(calendar: calendar)
        var intent = parser.parse(phrase, now: now)
        // In this dedicated surface, “tomar agua en diez minutos” is a reminder.
        if intent.action == .unknown { intent = parser.parse("Recuérdame " + phrase, now: now) }
        guard intent.action == .createReminder else {
            throw VoiceReminderError.invalid("Este control solo guarda recordatorios. Di qué recordar y cuándo.")
        }
        guard let title = intent.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceReminderError.invalid("Dime qué debo recordarte.")
        }
        guard intent.clarification == nil, let date = intent.date, date > now else {
            throw VoiceReminderError.invalid(intent.clarification ?? "Falta el día o la hora. Prueba: tomar agua dentro de diez minutos.")
        }
        return intent
    }

    @MainActor
    static func save(_ phrase: String, in context: ModelContext,
                     schedule: (Reminder) async throws -> Void = { try await LocalNotificationManager.shared.scheduleReminder($0) },
                     cancel: (Reminder) -> Void = { LocalNotificationManager.shared.cancelReminder($0) }) async throws {
        let intent = try parse(phrase)
        guard let title = intent.title, let date = intent.date else { return }
        let existing = try context.fetch(FetchDescriptor<Reminder>())
        if existing.contains(where: {
            !$0.isCompleted && $0.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                && abs($0.date.timeIntervalSince(date)) < 60 && $0.scheduleSlots == intent.recurrenceSlots
                && $0.isStrongAlarm == intent.isStrongAlarm
        }) { return }
        let reminder = Reminder(title: title, date: date, repeats: intent.isRepeating ?? false, isStrongAlarm: intent.isStrongAlarm)
        reminder.scheduleSlots = intent.recurrenceSlots
        do {
            try await schedule(reminder)
            context.insert(reminder)
            try context.save()
        } catch {
            cancel(reminder)
            context.rollback()
            throw error
        }
    }
}
