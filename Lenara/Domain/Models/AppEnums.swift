import Foundation

// MARK: - Memory Category
enum MemoryCategory: String, CaseIterable, Codable {
    case idea = "Idea"
    case note = "Nota"
    case project = "Proyecto"
    case person = "Persona"
    case decision = "Decisión"
    case goal = "Objetivo"
    case fact = "Dato"

    var icon: String {
        switch self {
        case .idea: return "lightbulb.fill"
        case .note: return "note.text"
        case .project: return "folder.fill"
        case .person: return "person.fill"
        case .decision: return "checkmark.seal.fill"
        case .goal: return "flag.fill"
        case .fact: return "info.circle.fill"
        }
    }
}

// MARK: - Memory Source
enum MemorySource: String, Codable {
    case manual = "Manual"
    case chat = "Chat"
    case voice = "Voz"
    case shared = "Compartido"
}

// MARK: - Task Status
enum TaskStatus: String, CaseIterable, Codable {
    case pending = "Pendiente"
    case completed = "Completada"

    mutating func toggle() {
        self = self == .pending ? .completed : .pending
    }
}

// MARK: - Task Priority
enum TaskPriority: String, CaseIterable, Codable {
    case low = "Baja"
    case medium = "Media"
    case high = "Alta"
}

// MARK: - Conversation Messages
enum MessageRole: String, Codable {
    case user = "user"
    case assistant = "assistant"
}
