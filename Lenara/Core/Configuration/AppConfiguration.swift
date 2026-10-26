import Foundation
import SwiftData

// MARK: - App Configuration
struct AppConfiguration {
    static let appName = "Lenara"
    static let appVersion = "0.1.0"
    static let bundleIdentifier = "com.lenara.app"

    // Privacy settings
    static let shouldEncryptLocalData = false // Will use iOS Keychain for sensitive data
    static let shouldSendAnalytics = false
    static let shouldUseiCloud = false

    // Feature flags
    static let enableLocalAI = true
    static let enableVoiceInput = true
    static let enableDocumentImport = false
}

// MARK: - Database Configuration
struct DatabaseConfiguration {
    static let schemaVersion = Schema.Version(1, 0, 0)
    static let maxMemories = 10000
    static let maxTasks = 1000
    static let maxReminders = 64 // iOS limit
    static let maxConversations = 500
}
