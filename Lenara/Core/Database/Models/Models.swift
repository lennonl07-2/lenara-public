import Foundation
import SwiftData

// MARK: - Memory Model
@Model
class Memory {
    var id: UUID
    var title: String
    var content: String
    var category: MemoryCategory?
    var tags: [String]
    var source: MemorySource?
    var confidence: Float?
    var createdAt: Date
    var updatedAt: Date
    var _description: String?

    init(
        title: String,
        content: String,
        category: MemoryCategory? = nil,
        tags: [String] = [],
        source: MemorySource? = .manual,
        confidence: Float? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.category = category
        self.tags = tags
        self.source = source
        self.confidence = confidence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self._description = nil
    }
}

// MARK: - Task Model
@Model
class Task {
    var id: UUID
    var title: String
    var detail: String?
    var status: TaskStatus
    var priority: TaskPriority
    var dueDate: Date?
    var createdAt: Date
    var completedAt: Date?

    func toggleStatus() {
        status.toggle()
        completedAt = status == .completed ? .now : nil
    }

    init(
        title: String,
        detail: String? = nil,
        status: TaskStatus = .pending,
        priority: TaskPriority = .medium,
        dueDate: Date? = nil,
        createdAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.detail = detail
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

// MARK: - Reminder Model
@Model
class Reminder {
    var id: UUID
    var title: String
    var date: Date
    var repeats: Bool
    var recurrenceData: Data?
    var snoozedUntil: Date?
    var acknowledgedAt: Date?
    var isStrongAlarm: Bool = false
    var isCompleted: Bool
    var notificationID: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        title: String,
        date: Date,
        repeats: Bool = false,
        isStrongAlarm: Bool = false,
        isCompleted: Bool = false,
        notificationID: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = UUID()
        self.title = title
        self.date = date
        self.repeats = repeats
        self.isStrongAlarm = isStrongAlarm
        self.isCompleted = isCompleted
        self.notificationID = notificationID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Conversation Message Model
@Model
class ConversationMessage {
    var id: UUID
    var content: String
    var isUser: Bool
    var createdAt: Date

    init(content: String, isUser: Bool, createdAt: Date = .now) {
        self.id = UUID()
        self.content = content
        self.isUser = isUser
        self.createdAt = createdAt
    }
}


extension Reminder {
    var scheduleSlots: [ReminderSlot] {
        get {
            if let recurrenceData, let slots = try? JSONDecoder().decode([ReminderSlot].self, from: recurrenceData) { return slots }
            guard repeats else { return [] }
            let time = Calendar.current.dateComponents([.hour, .minute], from: date)
            return [ReminderSlot(weekday: nil, hour: time.hour ?? 9, minute: time.minute ?? 0)]
        }
        set {
            recurrenceData = try? JSONEncoder().encode(newValue)
            repeats = !newValue.isEmpty
        }
    }
    func nextScheduledDate(after now: Date = .now) -> Date? {
        if repeats { return scheduleSlots.compactMap { $0.nextDate(after: now) }.min() }
        let next = snoozedUntil ?? date
        return next > now ? next : nil
    }
    var scheduleDescription: String { scheduleSlots.map(\.label).joined(separator: "\n") }
}

extension Reminder {
    var displayDate: Date {
        let next = nextScheduledDate()
        if let snooze = snoozedUntil, snooze > .now { return min(snooze, next ?? snooze) }
        return next ?? date
    }
    func hasUnacknowledgedStrongOccurrence(at now: Date) -> Bool {
        guard isStrongAlarm, !isCompleted else { return false }
        if let snooze = snoozedUntil, snooze > now { return false }
        let occurrence: Date
        if repeats {
            guard let last = scheduleSlots.compactMap({ slot in
                Calendar.current.nextDate(after: now, matching: slot.components, matchingPolicy: .nextTime,
                                          repeatedTimePolicy: .first, direction: .backward)
            }).max(), last >= createdAt else { return false }
            occurrence = last
        } else { occurrence = snoozedUntil ?? date }
        return occurrence <= now && (acknowledgedAt.map { $0 < occurrence } ?? true)
    }
}
