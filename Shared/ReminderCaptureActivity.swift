import ActivityKit
import AppIntents
import Foundation
import WidgetKit

enum ReminderCaptureControlState {
    static let kind = "com.lenara.capture-reminder"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSharedStore.appGroup) }
    static var isListening: Bool {
        guard let deadline = defaults?.object(forKey: "lenara.capture.deadline") as? Date else { return false }
        return deadline > .now
    }
    @available(iOS 18.0, *)
    static func setListening(_ listening: Bool) {
        defaults?.set(listening ? Date.now.addingTimeInterval(65) : Date.distantPast, forKey: "lenara.capture.deadline")
        ControlCenter.shared.reloadControls(ofKind: kind)
    }
}

struct ReminderCaptureAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var message: String
        var phase: Phase
    }

    enum Phase: String, Codable {
        case listening, ready, saving, saved, failed
    }

    var sessionID: UUID
}

@available(iOS 18.0, *)
struct StartReminderCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Dictar recordatorio"
    static var description = IntentDescription("Escucha y guarda un recordatorio sin abrir el chat.")
    static var openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        #if LENARA_APP
        ReminderNotificationRouter.shared.route = nil
        ReminderDictationRoute.shared.isPresented = true
        #endif
        return .result()
    }
}

@available(iOS 18.0, *)
struct SendReminderCaptureIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Enviar recordatorio"
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @Parameter(title: "Sesión") var sessionID: String

    init() { sessionID = "" }
    init(sessionID: UUID) { self.sessionID = sessionID.uuidString }

    @MainActor func perform() async throws -> some IntentResult {
        #if LENARA_APP
        await LockScreenReminderCapture.shared.send(sessionID: sessionID)
        #endif
        return .result()
    }
}

@available(iOS 18.0, *)
struct CancelReminderCaptureIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Cancelar dictado"
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @Parameter(title: "Sesión") var sessionID: String

    init() { sessionID = "" }
    init(sessionID: UUID) { self.sessionID = sessionID.uuidString }

    @MainActor func perform() async throws -> some IntentResult {
        #if LENARA_APP
        await LockScreenReminderCapture.shared.cancel(sessionID: sessionID)
        #endif
        return .result()
    }
}
