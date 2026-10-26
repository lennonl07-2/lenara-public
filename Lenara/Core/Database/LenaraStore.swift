import SwiftData

enum LenaraStore {
    // The UI and background intents must share the same container and schema.
    @MainActor static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Memory.self, Task.self, Reminder.self, ConversationMessage.self)
        } catch {
            fatalError("No se pudo abrir la base de datos de Lenara: \(error)")
        }
    }()
}
