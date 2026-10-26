import SwiftUI
import SwiftData
import ActivityKit

/// The control opens only this surface; sending never creates a chat message.
struct WidgetVoiceCaptureScreen: View {
    @StateObject private var capture = VoiceCaptureModel()
    @State private var isSaving = false
    @State private var actionError: String?
    @State private var previousIdleTimerState: Bool?
    let onClose: () -> Void

    var body: some View {
        ZStack {
            LenaraColors.background.ignoresSafeArea()
            VStack(spacing: 22) {
                HStack {
                    Text("Recordatorio por voz").font(.rounded(.headline))
                    Spacer()
                    Button("Cancelar") { capture.cancel(); onClose() }
                        .disabled(isSaving)
                }
                Spacer(minLength: 12)
                Image("LenaraLockLogo").resizable().scaledToFit()
                    .frame(width: 100, height: 100).foregroundStyle(LenaraColors.logoMint)
                    .accessibilityHidden(true)
                Text(isSaving ? "Guardando…" : capture.isRecording ? "Te escucho" : "Tu recordatorio")
                    .font(.rounded(.title2))
                Text("Dime qué recordar y cuándo. Toca Enviar al terminar.")
                    .foregroundStyle(LenaraColors.textSecondary).multilineTextAlignment(.center)
                ScrollView {
                    Text(capture.transcript.isEmpty ? "Por ejemplo: tomar agua dentro de diez minutos." : capture.transcript)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(LenaraColors.surface, in: RoundedRectangle(cornerRadius: 18))
                }
                .frame(maxHeight: 220)
                if let error = actionError ?? capture.errorMessage {
                    Text(error).font(.callout).foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 12)
                Button {
                    _Concurrency.Task { await send() }
                } label: {
                    Label(isSaving ? "Guardando…" : "Enviar", systemImage: "arrow.up.circle.fill")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(LenaraColors.onAccent)
                        .background(LenaraColors.accent, in: Capsule())
                }
                .disabled(isSaving || capture.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Volver a dictar") {
                    capture.cancel()
                    actionError = nil
                    _Concurrency.Task { await capture.start() }
                }
                .disabled(isSaving)
            }
            .padding(24).foregroundStyle(LenaraColors.textPrimary)
        }
        .task {
            previousIdleTimerState = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            // Retire any activity left over from the previous background-only flow.
            if #available(iOS 18.0, *) {
                await LockScreenReminderCapture.shared.endForForeground()
            }
            guard !_Concurrency.Task.isCancelled else { return }
            await capture.start()
        }
        .onDisappear {
            capture.cancel()
            if let previousIdleTimerState {
                UIApplication.shared.isIdleTimerDisabled = previousIdleTimerState
            }
        }
    }

    @MainActor private func send() async {
        guard !isSaving else { return }
        isSaving = true
        actionError = nil
        capture.stop()
        for _ in 0..<40 {
            if capture.didFinishTranscription || capture.errorMessage != nil { break }
            try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
        }
        do {
            if let error = capture.errorMessage { throw VoiceReminderError.invalid(error) }
            guard capture.didFinishTranscription else {
                throw VoiceReminderError.invalid("No se completó la transcripción. Vuelve a dictar.")
            }
            let phrase = VoiceReminderService.requestBeforeSendCommand(capture.transcript) ?? capture.transcript
            let context = ModelContext(LenaraStore.container)
            context.autosaveEnabled = false
            try await VoiceReminderService.save(phrase, in: context)
            capture.cancel()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onClose()
        } catch {
            actionError = error.localizedDescription
            isSaving = false
        }
    }
}
