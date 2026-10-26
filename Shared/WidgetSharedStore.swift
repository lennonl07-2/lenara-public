import Foundation

struct WidgetChecklistItem: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var isCompleted: Bool
}

struct WidgetTaskSnapshot: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var items: [WidgetChecklistItem]
    var updatedAt: Date
}

enum TaskChecklistCodec {
    private static let prefix = "lenara-checklist-v1:"

    struct Payload: Codable {
        var description: String
        var items: [WidgetChecklistItem]
    }

    static func decode(_ detail: String?) -> Payload {
        guard let detail, detail.hasPrefix(prefix),
              let data = Data(base64Encoded: String(detail.dropFirst(prefix.count))),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return Payload(description: detail ?? "", items: [])
        }
        return payload
    }

    static func encode(description: String, items: [WidgetChecklistItem]) -> String? {
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanItems = items.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !cleanItems.isEmpty else { return cleanDescription.isEmpty ? nil : cleanDescription }
        guard let data = try? JSONEncoder().encode(Payload(description: cleanDescription, items: cleanItems)) else { return cleanDescription }
        return prefix + data.base64EncodedString()
    }
}

enum WidgetSharedStore {
    static let appGroup = "group.com.lenara.shared"
    private static let tasksKey = "lenara.widget.tasks.v1"
    private static let selectedTaskKey = "lenara.widget.selectedTask.v1"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func readTasks() -> [WidgetTaskSnapshot] {
        guard let data = defaults?.data(forKey: tasksKey),
              let tasks = try? JSONDecoder().decode([WidgetTaskSnapshot].self, from: data) else { return [] }
        return tasks
    }

    static func writeTasks(_ tasks: [WidgetTaskSnapshot]) {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        defaults?.set(data, forKey: tasksKey)
    }

    static func selectedTaskID() -> String? {
        guard let value = defaults?.string(forKey: selectedTaskKey), !value.isEmpty else { return nil }
        return value
    }

    static func selectTask(id: String) {
        defaults?.set(id, forKey: selectedTaskKey)
    }

    static func clearSelectedTask() {
        // An empty value records an explicit deselection, so the app won't
        // automatically choose a task again on its next refresh.
        defaults?.set("", forKey: selectedTaskKey)
    }

    static func clearAll() {
        defaults?.removeObject(forKey: tasksKey)
        defaults?.removeObject(forKey: selectedTaskKey)
    }

    static func selectDefaultTaskIfNeeded(id: String) {
        guard defaults?.object(forKey: selectedTaskKey) == nil else { return }
        defaults?.set(id, forKey: selectedTaskKey)
    }

    static func toggle(itemID: String) {
        var tasks = readTasks()
        for taskIndex in tasks.indices {
            guard let itemIndex = tasks[taskIndex].items.firstIndex(where: { $0.id == itemID }) else { continue }
            tasks[taskIndex].items[itemIndex].isCompleted.toggle()
            tasks[taskIndex].updatedAt = .now
            writeTasks(tasks)
            return
        }
    }
}
