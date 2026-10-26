import Foundation
import SwiftData

// MARK: - Memory Service
class MemoryService {
    func createMemory(
        in context: ModelContext,
        title: String,
        content: String,
        category: MemoryCategory? = nil,
        tags: [String] = []
    ) -> Memory {
        let memory = Memory(
            title: title,
            content: content,
            category: category,
            tags: tags
        )
        context.insert(memory)
        return memory
    }

    func updateMemory(_ memory: Memory, title: String? = nil, content: String? = nil, category: MemoryCategory? = nil, tags: [String]? = nil) {
        if let title = title { memory.title = title }
        if let content = content { memory.content = content }
        if let category = category { memory.category = category }
        if let tags = tags { memory.tags = tags }
        memory.updatedAt = .now
    }

    func deleteMemory(_ memory: Memory, from context: ModelContext) {
        context.delete(memory)
    }

    func fetchAll(in context: ModelContext) -> [Memory] {
        let descriptor = SortDescriptor(\Memory.createdAt, order: .reverse)
        do {
            return try context.fetch(FetchDescriptor<Memory>(sortBy: [descriptor]))
        } catch {
            return []
        }
    }

    func searchMemory(in context: ModelContext, query: String) -> [Memory] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        do {
            let all = try context.fetch(FetchDescriptor<Memory>())
            return all.filter { memory in
                let fields = [memory.title, memory.content] + memory.tags
                return terms.allSatisfy { term in fields.contains { $0.localizedCaseInsensitiveContains(term) } }
            }.sorted { lhs, rhs in
                func score(_ memory: Memory) -> Int {
                    let title = memory.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    return terms.reduce(0) { $0 + (title.hasPrefix($1) ? 3 : title.contains($1) ? 2 : 0) }
                }
                let leftScore = score(lhs), rightScore = score(rhs)
                return leftScore == rightScore ? lhs.updatedAt > rhs.updatedAt : leftScore > rightScore
            }
        } catch {
            return []
        }
    }

    func count(in context: ModelContext) -> Int {
        do {
            return try context.fetchCount(FetchDescriptor<Memory>())
        } catch {
            return 0
        }
    }
}

// MARK: - Task Service
class TaskService {
    func createTask(
        in context: ModelContext,
        title: String,
        detail: String? = nil,
        priority: TaskPriority = .medium,
        dueDate: Date? = nil
    ) -> Task {
        let task = Task(title: title, detail: detail, priority: priority, dueDate: dueDate)
        context.insert(task)
        return task
    }

    func updateTaskStatus(_ task: Task, to status: TaskStatus) {
        task.status = status
        if status == .completed {
            task.completedAt = .now
        } else {
            task.completedAt = nil
        }
    }

    func deleteTask(_ task: Task, from context: ModelContext) {
        context.delete(task)
    }

    func fetchAll(in context: ModelContext) -> [Task] {
        let descriptor = SortDescriptor(\Task.dueDate, order: .forward)
        do {
            return try context.fetch(FetchDescriptor<Task>(sortBy: [descriptor]))
        } catch {
            return []
        }
    }

    func pendingCount(in context: ModelContext) -> Int {
        do {
            let all = try context.fetch(FetchDescriptor<Task>())
            return all.filter { $0.status == .pending }.count
        } catch {
            return 0
        }
    }
}

// MARK: - Reminder Service
class ReminderService {
    func createReminder(
        in context: ModelContext,
        title: String,
        date: Date,
        repeats: Bool = false
    ) async throws -> Reminder {
        let reminder = Reminder(title: title, date: date, repeats: repeats)
        context.insert(reminder)
        try context.save()
        try await scheduleNotification(reminder, in: context)
        return reminder
    }

    func scheduleNotification(_ reminder: Reminder, in context: ModelContext) async throws {
        guard !reminder.isCompleted else { return }
        try await LocalNotificationManager.shared.scheduleReminder(reminder)
        try context.save()
    }

    func cancelNotification(_ reminder: Reminder) {
        LocalNotificationManager.shared.cancelReminder(reminder)
    }

    func fetchAll(in context: ModelContext) -> [Reminder] {
        let descriptor = SortDescriptor(\Reminder.date, order: .forward)
        do {
            return try context.fetch(FetchDescriptor<Reminder>(sortBy: [descriptor]))
        } catch {
            return []
        }
    }

    func upcoming(in context: ModelContext, count: Int) -> [Reminder] {
        let descriptor = SortDescriptor(\Reminder.date, order: .forward)
        do {
            let all = try context.fetch(FetchDescriptor<Reminder>(sortBy: [descriptor]))
            let upcoming = all.filter { r in
                r.date > .now && !r.isCompleted
            }
            return Array(upcoming.prefix(count))
        } catch {
            return []
        }
    }
}
