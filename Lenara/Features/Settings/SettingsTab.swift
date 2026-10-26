import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UserNotifications
import Combine
import UIKit
import AVFoundation
import WidgetKit

struct SettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var models = LocalModelManager.shared
    @AppStorage("lenara.userName") private var userName = ""
    @AppStorage("lenara.notificationSound") private var notificationSound = "NotificationAurora.wav"
    @State private var previewPlayer: AVAudioPlayer?
    @State private var exportDocument: LenaraExportDocument?
    @State private var showingExporter = false
    @State private var showingFullReset = false
    @State private var message: String?
    @State private var notificationStatus = "Comprobando…"
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section("Perfil") {
                    TextField("Tu nombre", text: $userName).autocorrectionDisabled()
                }
                Section("Recordatorios") {
                    Picker("Sonido", selection: $notificationSound) {
                        ForEach(NotificationSoundLibrary.sounds) { sound in
                            Text(sound.title).tag(sound.fileName)
                        }
                        Text("Predeterminado de iOS").tag("default")
                        Text("Sin sonido").tag("silent")
                    }
                    Button { previewSelectedSound() } label: {
                        Label("Probar sonido", systemImage: "play.circle")
                    }
                    Text("Sonidos originales de Lenara. El volumen final depende de los ajustes de sonido del iPhone.")
                        .font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("Notificaciones", value: notificationStatus)
                    if notificationStatus != "Permitidas" {
                        if notificationStatus == "Aún no solicitado" {
                            Button("Activar notificaciones") {
                                _Concurrency.Task {
                                    let granted = await LocalNotificationManager.shared.requestAuthorization()
                                    notificationStatus = granted ? "Permitidas" : "Desactivadas en iOS"
                                    if granted {
                                        let reminders = (try? modelContext.fetch(FetchDescriptor<Reminder>())) ?? []
                                        await LocalNotificationManager.shared.refreshScheduledReminderCopy(reminders)
                                        try? modelContext.save()
                                    }
                                    await refreshNotificationStatus()
                                }
                            }
                        } else {
                            Button("Abrir ajustes de iOS") {
                                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                    Text("Lenara programa avisos locales. iOS controla cuándo se muestran y cómo suenan.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("IA local") {
                    LabeledContent("Espacio usado", value: ByteCountFormatter.string(fromByteCount: models.modelsBytes, countStyle: .file))
                    recommendedModelDetails
                    Link("Ver ficha del modelo en Hugging Face", destination: URL(string: "https://huggingface.co/\(LocalModel.recommended.repository)")!)
                    Text("Licencia del modelo: Apache 2.0")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let error = models.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(LenaraColors.error)
                    }
                }
                Section("Datos y privacidad") {
                    Button("Exportar recuerdos y agenda") { prepareExport() }
                    Button("Eliminar todo…", role: .destructive) { showingFullReset = true }
                }
                Section("Acerca de") {
                    LabeledContent("Versión", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                    Text("Lenara es tu asistente personal. Usa modelos abiertos que se ejecutan en este iPhone; tus recuerdos, tareas y conversaciones se guardan localmente y no se envían a servidores de IA. Creada y desarrollada por Lennon Linares.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://www.instagram.com/lennonl1306/")!) {
                        Label("Invítame un ceviche", systemImage: "fish")
                    }
                }
            }
            .navigationTitle("Ajustes")
            .task {
                models.refresh()
                if !["silent", "default"].contains(notificationSound),
                   !NotificationSoundLibrary.sounds.contains(where: { $0.fileName == notificationSound }),
                   let firstSound = NotificationSoundLibrary.sounds.first {
                    notificationSound = firstSound.fileName
                }
                await refreshNotificationStatus()
            }
            .onChange(of: notificationSound) { _, _ in
                _Concurrency.Task { @MainActor in
                    let reminders = (try? modelContext.fetch(FetchDescriptor<Reminder>())) ?? []
                    await LocalNotificationManager.shared.reschedulePendingRemindersWithSelectedSound(reminders)
                    try? modelContext.save()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    models.refresh()
                    _Concurrency.Task { await refreshNotificationStatus() }
                }
            }
            .fileExporter(isPresented: $showingExporter, document: exportDocument, contentType: .json, defaultFilename: "lenara-export") { result in
                if case .failure(let error) = result { message = "No se pudo exportar: \(error.localizedDescription)" }
            }
            .confirmationDialog("¿Deseas eliminar todo?", isPresented: $showingFullReset, titleVisibility: .visible) {
                Button("Sí, eliminar también el modelo", role: .destructive) { deleteAllData(alsoDeleteModel: true) }
                Button("No, conservar el modelo", role: .destructive) { deleteAllData(alsoDeleteModel: false) }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se borrarán tus recuerdos, tareas, recordatorios, conversaciones y preferencias, y Lenara volverá a la bienvenida. iOS no permite que una app revoque permisos ya concedidos; los permisos denegados se gestionan en Ajustes del iPhone.")
            }
            .alert("Lenara", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("Aceptar", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
        }
    }

    @ViewBuilder private var recommendedModelDetails: some View {
        let model = LocalModel.recommended
        let isDownloaded = models.downloadedIDs.contains(model.id)
        let isDownloading = models.downloadingID == model.id

        VStack(alignment: .leading, spacing: 10) {
            Text(model.name)
                .font(.headline)
                .foregroundStyle(LenaraColors.textPrimary)
            Text("Modelo abierto de instrucciones (1.7B, Q2_K), preparado para ejecutar respuestas de IA en el iPhone con un tamaño de descarga moderado.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if isDownloaded {
                Label("Modelo descargado", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(LenaraColors.logoMint)
                Button("Eliminar modelo descargado", role: .destructive) {
                    models.delete(model)
                    _Concurrency.Task { await LocalLlamaEngine.shared.unload() }
                }
                .font(.footnote)
            } else if isDownloading {
                ProgressView(value: models.downloadProgress)
                Text("Descargando… \(Int(models.downloadProgress * 100)) %")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Cancelar descarga") { models.cancelDownload() }
                    .font(.footnote)
            } else {
                Text("Aún no tienes el modelo descargado. Descárgalo para activar las respuestas generativas de IA local.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    models.download(model)
                } label: {
                    Label("Descargar modelo (\(model.sizeLabel))", systemImage: "arrow.down.circle")
                }
            }

            Text("La primera descarga necesita internet. Después, el modelo procesa tus consultas aquí y puede funcionar sin conexión. Tus mensajes nunca salen de tu dispositivo.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func previewSelectedSound() {
        guard let sound = NotificationSoundLibrary.sounds.first(where: { $0.fileName == notificationSound }) else {
            if notificationSound == "silent" { message = "Está seleccionado «Sin sonido». Elige un sonido para escucharlo." }
            else if notificationSound == "default" { message = "Está seleccionado el sonido predeterminado de iOS." }
            return
        }
        guard let url = Bundle.main.url(forResource: sound.fileName, withExtension: nil) else {
            message = "No se encontró el archivo de sonido «\(sound.fileName)» dentro de Lenara. Reinstala la app para actualizar sus sonidos."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            previewPlayer = try AVAudioPlayer(contentsOf: url)
            previewPlayer?.volume = 1
            guard previewPlayer?.prepareToPlay() == true, previewPlayer?.play() == true else {
                message = "iOS no pudo iniciar la reproducción. Sube el volumen multimedia e inténtalo otra vez."
                return
            }
        } catch { message = "No se pudo reproducir el sonido: \(error.localizedDescription)" }
    }

    @MainActor private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            if settings.alertSetting != .enabled { notificationStatus = "Avisos desactivados en iOS" }
            else if settings.soundSetting != .enabled { notificationStatus = "Sonidos desactivados en iOS" }
            else { notificationStatus = "Permitidas" }
        case .denied: notificationStatus = "Desactivadas en iOS"
        case .notDetermined: notificationStatus = "Aún no solicitado"
        @unknown default: notificationStatus = "Estado desconocido"
        }
    }

    private func prepareExport() {
        do {
            let memories = try modelContext.fetch(FetchDescriptor<Memory>()).map {
                MemoryExport(title: $0.title, content: $0.content, category: $0.category?.rawValue, tags: $0.tags, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            }
            let tasks = try modelContext.fetch(FetchDescriptor<Task>()).map {
                TaskExport(title: $0.title, detail: $0.detail, status: $0.status.rawValue, priority: $0.priority.rawValue, dueDate: $0.dueDate, createdAt: $0.createdAt)
            }
            let reminders = try modelContext.fetch(FetchDescriptor<Reminder>()).map {
                ReminderExport(title: $0.title, date: $0.date, repeats: $0.repeats, isCompleted: $0.isCompleted, createdAt: $0.createdAt)
            }
            let payload = LenaraExport(version: 1, exportedAt: .now, memories: memories, tasks: tasks, reminders: reminders)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            exportDocument = LenaraExportDocument(data: try encoder.encode(payload))
            showingExporter = true
        } catch { message = "No se pudieron leer los datos: \(error.localizedDescription)" }
    }

    private func deleteAllData(alsoDeleteModel: Bool) {
        do {
            try modelContext.fetch(FetchDescriptor<Memory>()).forEach(modelContext.delete)
            try modelContext.fetch(FetchDescriptor<Task>()).forEach(modelContext.delete)
            try modelContext.fetch(FetchDescriptor<Reminder>()).forEach(modelContext.delete)
            try modelContext.fetch(FetchDescriptor<ConversationMessage>()).forEach(modelContext.delete)
            try modelContext.save()
            LocalNotificationManager.shared.cancelAll()
            WidgetSharedStore.clearAll()
            WidgetCenter.shared.reloadAllTimelines()

            let defaults = UserDefaults.standard
            let appKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("lenara.") }
            _Concurrency.Task { @MainActor in
                if alsoDeleteModel {
                    await LocalLlamaEngine.shared.unload()
                    await models.deleteAllModels()
                }
                for key in appKeys where key != "lenara.onboardingComplete" && !(key == "lenara.localModel.selected" && !alsoDeleteModel) {
                    defaults.removeObject(forKey: key)
                }
                defaults.removeObject(forKey: "lenara.onboardingComplete")
            }
        } catch {
            modelContext.rollback()
            message = "No se pudieron eliminar los datos: \(error.localizedDescription)"
        }
    }
}

private struct LenaraExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct LenaraExport: Encodable {
    let version: Int
    let exportedAt: Date
    let memories: [MemoryExport]
    let tasks: [TaskExport]
    let reminders: [ReminderExport]
}
private struct MemoryExport: Encodable { let title: String; let content: String; let category: String?; let tags: [String]; let createdAt: Date; let updatedAt: Date }
private struct TaskExport: Encodable { let title: String; let detail: String?; let status: String; let priority: String; let dueDate: Date?; let createdAt: Date }
private struct ReminderExport: Encodable { let title: String; let date: Date; let repeats: Bool; let isCompleted: Bool; let createdAt: Date }
