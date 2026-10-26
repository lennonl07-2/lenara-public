import ActivityKit
import AVFoundation
import Combine
import Speech
import SwiftData
import UserNotifications

@available(iOS 18.0, *)
@MainActor
final class LockScreenReminderCapture {
    static let shared = LockScreenReminderCapture()
    private let capture = VoiceCaptureModel()
    private var activity: Activity<ReminderCaptureAttributes>?
    private var timeout: _Concurrency.Task<Void, Never>?
    private var voiceSend: _Concurrency.Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()
    private var busy = false

    private init() {
        capture.$transcript.sink { [weak self] transcript in
            guard let self, !self.busy else { return }
            self.voiceSend?.cancel()
            guard VoiceReminderService.requestBeforeSendCommand(transcript) != nil else { return }
            self.voiceSend = _Concurrency.Task { @MainActor [weak self] in
                do { try await _Concurrency.Task.sleep(nanoseconds: 700_000_000) } catch { return }
                guard let self, let current = self.activity, !self.busy else { return }
                await self.send(sessionID: current.attributes.sessionID.uuidString)
            }
        }.store(in: &subscriptions)
        capture.$errorMessage.compactMap { $0 }.sink { [weak self] message in
            _Concurrency.Task { @MainActor in
                guard let self, let activity = self.activity, !self.busy else { return }
                await self.finish(activity, message: message, phase: .failed)
            }
        }.store(in: &subscriptions)
        capture.$didFinishTranscription.filter { $0 }.sink { [weak self] _ in
            _Concurrency.Task { @MainActor in
                guard let self, let activity = self.activity, !self.busy else { return }
                await activity.update(ActivityContent(state: .init(message: "Pulsa otra vez el control de Lenara para enviar", phase: .ready), staleDate: nil))
            }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification).sink { [weak self] notification in
            guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  type == AVAudioSession.InterruptionType.began.rawValue else { return }
            _Concurrency.Task { @MainActor in
                guard let self, let activity = self.activity, !self.busy else { return }
                await self.finish(activity, message: "Dictado interrumpido. Vuelve a intentarlo.", phase: .failed)
            }
        }.store(in: &subscriptions)
    }

    func startOrSend() async throws {
        if let current = activity {
            await send(sessionID: current.attributes.sessionID.uuidString)
        } else {
            try await start()
        }
    }

    func endForForeground() async {
        if let current = activity { await cancel(sessionID: current.attributes.sessionID.uuidString) }
        for old in Activity<ReminderCaptureAttributes>.activities {
            await old.end(nil, dismissalPolicy: .immediate)
        }
        ReminderCaptureControlState.setListening(false)
    }

    private func start() async throws {
        guard !busy, activity == nil else { return }
        busy = true
        defer { busy = false }
        guard UserDefaults.standard.bool(forKey: "lenara.onboardingComplete"),
              SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioApplication.shared.recordPermission == .granted else {
            throw VoiceReminderError.invalid("Abre Lenara una vez y activa los permisos de micrófono y reconocimiento de voz.")
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            throw VoiceReminderError.invalid("Activa las notificaciones de Lenara en Ajustes para recibir el recordatorio.")
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw VoiceReminderError.invalid("Activa las actividades en vivo de Lenara en Ajustes.")
        }
        // A previous process may have been terminated by iOS while recording.
        for old in Activity<ReminderCaptureAttributes>.activities {
            await old.end(nil, dismissalPolicy: .immediate)
        }
        let next = try Activity.request(attributes: ReminderCaptureAttributes(sessionID: UUID()),
            content: ActivityContent(state: .init(message: "Escuchando… Di «Lenara, enviar» al terminar", phase: .listening), staleDate: .now.addingTimeInterval(60)), pushType: nil)
        activity = next
        await capture.start()
        if let error = capture.errorMessage {
            await finish(next, message: error, phase: .failed)
            return
        }
        ReminderCaptureControlState.setListening(true)
        timeout = _Concurrency.Task { [weak self] in
            do { try await _Concurrency.Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
            guard let self, self.activity?.id == next.id, !self.busy else { return }
            await self.finish(next, message: "Dictado cancelado por tiempo. No se guardó nada.", phase: .failed)
        }
    }

    func send(sessionID: String) async {
        guard !busy else { return }
        guard let current = activity, current.attributes.sessionID.uuidString == sessionID else {
            await dismissExpired(sessionID)
            return
        }
        busy = true
        defer { busy = false }
        timeout?.cancel()
        await current.update(ActivityContent(state: .init(message: "Guardando…", phase: .saving), staleDate: nil))
        capture.stop()
        // Wait for the recognizer's final result; never silently save a partial sentence.
        for _ in 0..<40 {
            if capture.didFinishTranscription || capture.errorMessage != nil { break }
            try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
        }
        do {
            if let error = capture.errorMessage { throw VoiceReminderError.invalid(error) }
            guard capture.didFinishTranscription else {
                throw VoiceReminderError.invalid("No se completó el dictado. Vuelve a intentarlo.")
            }
            let phrase = VoiceReminderService.requestBeforeSendCommand(capture.transcript) ?? capture.transcript
            capture.cancel()
            // A separate context keeps rollback isolated from unsaved UI edits.
            let context = ModelContext(LenaraStore.container)
            context.autosaveEnabled = false
            try await VoiceReminderService.save(phrase, in: context)
            await finish(current, message: "Guardado", phase: .saved)
        } catch {
            await finish(current, message: error.localizedDescription, phase: .failed)
        }
    }

    func cancel(sessionID: String) async {
        guard !busy else { return }
        guard let current = activity, current.attributes.sessionID.uuidString == sessionID else {
            await dismissExpired(sessionID)
            return
        }
        busy = true
        timeout?.cancel()
        voiceSend?.cancel()
        capture.cancel()
        ReminderCaptureControlState.setListening(false)
        await current.end(nil, dismissalPolicy: .immediate)
        activity = nil
        busy = false
    }

    private func finish(_ current: Activity<ReminderCaptureAttributes>, message: String,
                        phase: ReminderCaptureAttributes.Phase) async {
        guard activity?.id == current.id else { return }
        timeout?.cancel()
        voiceSend?.cancel()
        capture.cancel()
        ReminderCaptureControlState.setListening(false)
        // Clear before awaiting so a delayed callback cannot end a new recording.
        activity = nil
        await current.end(ActivityContent(state: .init(message: message, phase: phase), staleDate: nil),
                          dismissalPolicy: .after(.now.addingTimeInterval(phase == .saved ? 2 : 15)))
    }

    private func dismissExpired(_ sessionID: String) async {
        for old in Activity<ReminderCaptureAttributes>.activities where old.attributes.sessionID.uuidString == sessionID {
            await old.end(ActivityContent(state: .init(message: "El dictado terminó. Vuelve a intentarlo.", phase: .failed), staleDate: nil),
                          dismissalPolicy: .after(.now.addingTimeInterval(10)))
        }
    }
}
