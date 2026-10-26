import SwiftUI
import Speech
import AVFoundation
import UIKit

@MainActor
final class VoiceCaptureModel: NSObject, ObservableObject, SFSpeechRecognitionTaskDelegate {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var isWorking = false
    @Published var didFinishTranscription = false
    @Published var errorMessage: String?

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-PE"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var previousIdleTimerState: Bool?

    func start() async {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            errorMessage = "El reconocimiento sin conexión no está disponible para español en este dispositivo."
            return
        }
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speechAllowed else { errorMessage = "Activa el permiso de reconocimiento de voz en Ajustes de iOS."; return }
        let micAllowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard micAllowed else { errorMessage = "Activa el permiso del micrófono en Ajustes de iOS."; return }
        guard !_Concurrency.Task.isCancelled else { return }

        do {
            transcript = ""
            didFinishTranscription = false
            errorMessage = nil
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true)
            let nextRequest = SFSpeechAudioBufferRecognitionRequest()
            nextRequest.shouldReportPartialResults = true
            nextRequest.requiresOnDeviceRecognition = true
            nextRequest.contextualStrings = ["next", "finish", "siguiente", "terminar", "finalizar", "Lenara", "Lenara enviar"]
            request = nextRequest
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                nextRequest.append(buffer)
            }
            tapInstalled = true
            recognitionTask = recognizer.recognitionTask(with: nextRequest, delegate: self)
            engine.prepare()
            try engine.start()
            // UIKit controls idle sleep only while Lenara is in the foreground.
            // A Live Activity cannot hold the system Lock Screen awake.
            previousIdleTimerState = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            isRecording = true
        } catch {
            errorMessage = "No se pudo iniciar la grabación. \(error.localizedDescription)"
            finishAudio()
        }
    }

    func stop() {
        guard isRecording else { return }
        finishAudio()
        request?.endAudio()
        isWorking = true
    }

    func cancel() {
        finishAudio()
        let taskToCancel = recognitionTask
        recognitionTask = nil
        taskToCancel?.cancel()
        request = nil
        transcript = ""
        isWorking = false
        didFinishTranscription = false
    }

    private func finishAudio() {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        isRecording = false
        if let previousIdleTimerState {
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerState
            self.previousIdleTimerState = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription) {
        _Concurrency.Task { @MainActor [weak self] in
            guard let self, self.recognitionTask === task else { return }
            self.transcript = transcription.formattedString
        }
    }

    nonisolated func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition recognitionResult: SFSpeechRecognitionResult) {
        _Concurrency.Task { @MainActor [weak self] in
            guard let self, self.recognitionTask === task else { return }
            self.transcript = recognitionResult.bestTranscription.formattedString
            self.finishAudio()
            self.isWorking = false
            self.didFinishTranscription = true
        }
    }

    nonisolated func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
        _Concurrency.Task { @MainActor [weak self] in
            guard let self, self.recognitionTask === task else { return }
            self.isWorking = false
            self.finishAudio()
            if successfully, !self.transcript.isEmpty { self.didFinishTranscription = true }
            if !successfully, self.transcript.isEmpty { self.errorMessage = "No se pudo completar la transcripción. Inténtalo otra vez." }
        }
    }

    nonisolated func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didCancelWithError error: Error) {
        _Concurrency.Task { @MainActor [weak self] in
            guard let self, self.recognitionTask === task, self.isRecording else { return }
            self.errorMessage = "No se pudo transcribir el audio: \(error.localizedDescription)"
            self.finishAudio()
        }
    }
}

struct VoiceCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var capture = VoiceCaptureModel()
    var autoStart = false
    let onSendToChat: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
            LenaraColors.background.ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: capture.isRecording ? "waveform" : "mic")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(LenaraColors.logoMint)
                    .frame(width: 78, height: 78)
                    .background(LenaraColors.surface, in: Circle())
                    .accessibilityHidden(true)

                Text(capture.isRecording ? "Te escucho" : capture.isWorking ? "Preparando tu mensaje…" : "Dime qué necesitas")
                    .font(.rounded(.title3))
                    .foregroundStyle(LenaraColors.textPrimary)

                if !capture.transcript.isEmpty {
                    Text(capture.transcript)
                        .font(.body)
                        .foregroundStyle(LenaraColors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                        .padding(14)
                        .background(LenaraColors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Button {
                    if capture.isRecording { capture.stop() }
                    else { _Concurrency.Task { await capture.start() } }
                } label: {
                    Label(capture.isRecording ? "Detener y enviar" : "Empezar a hablar", systemImage: capture.isRecording ? "stop.fill" : "mic.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(LenaraColors.onAccent)
                        .background(LenaraColors.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(capture.isWorking)

                Text("La transcripción se procesa en el dispositivo. El audio no se conserva.")
                    .font(.footnote)
                    .foregroundStyle(LenaraColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(22)
            }
            .navigationTitle("Voz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LenaraColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { capture.cancel(); dismiss() }
                }
            }
            .onChange(of: capture.didFinishTranscription) { _, isFinished in
                guard isFinished else { return }
                let text = capture.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { capture.errorMessage = "No se detectó voz. Puedes volver a intentarlo."; return }
                capture.cancel()
                dismiss()
                onSendToChat(text)
            }
            .onAppear {
                guard autoStart else { return }
                _Concurrency.Task { await capture.start() }
            }
            .onDisappear { capture.cancel() }
            .alert("Voz", isPresented: Binding(get: { capture.errorMessage != nil }, set: { if !$0 { capture.errorMessage = nil } })) {
                Button("Aceptar", role: .cancel) { capture.errorMessage = nil }
                if capture.errorMessage != nil { Button("Ajustes de iOS") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) } }
            } message: { Text(capture.errorMessage ?? "") }
        }
        .presentationBackground(LenaraColors.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

