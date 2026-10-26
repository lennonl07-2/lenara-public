import SwiftUI
import SwiftData
import Combine

// MARK: - Chat Sheet
struct ChatSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ConversationMessage.createdAt, order: .forward) private var messages: [ConversationMessage]
    @Query(sort: \Reminder.date) private var reminders: [Reminder]
    @FocusState private var inputFocused: Bool
    @State private var inputFrame: CGRect = .zero
    @State private var inputText = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showingClearConfirmation = false
    @State private var showingVoiceCapture = false
    @State private var pendingReminderTitle: String?
    @State private var pendingReminderRequest: String?
    @State private var animatedAssistantID: UUID?
    @State private var animatedAssistantText = ""
    @State private var showOlderMessages = false
    @State private var clockNow = Date.now
    @AppStorage("lenara.userName") private var userName = ""

    private let intentParser = IntentParser()
    private let initialText: String

    private var visibleMessages: [ConversationMessage] {
        showOlderMessages ? messages : Array(messages.suffix(6))
    }

    private var activeStrongAlarm: Reminder? {
        reminders.first { $0.hasUnacknowledgedStrongOccurrence(at: clockNow) }
    }

    init(initialText: String = "") {
        self.initialText = initialText
        _inputText = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
        VStack(spacing: 0) {
            if let activeStrongAlarm { strongAlarmBanner(activeStrongAlarm) }
            // Messages list
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    if messages.count > 6 && !showOlderMessages {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showOlderMessages = true }
                        } label: {
                            Label("Ver anteriores", systemImage: "arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(LenaraColors.logoMint)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial)
                        }
                        .buttonStyle(.plain)
                    }
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if messages.isEmpty {
                                Spacer().frame(height: 40)
                                startScreen
                            } else {
                                ForEach(visibleMessages) { message in
                                    messageBubble(message)
                                        .id(message.id)
                                }
                            }
                        }
                        .padding()
                        .id("bottom")
                    }
                    .scrollDisabled(!showOlderMessages)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onChange(of: showOlderMessages) { _, showingOlder in
                        if showingOlder {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: animatedAssistantText.count) { _, _ in
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    .onTapGesture { inputFocused = false }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: isProcessing) { _, processing in
                        if processing {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Divider()
                .background(LenaraColors.divider)

            // Input bar
            inputBar
        }
        .background(LenaraColors.background)
        .onAppear {
            inputText = initialText
            clockNow = .now
            if !initialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { sendMessage() }
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { clockNow = $0 }
        .sheet(isPresented: $showingVoiceCapture) {
            VoiceCaptureSheet { dictatedText in
                inputText = dictatedText
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { sendMessage() }
            }
        }
        .alert("No se pudo completar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Aceptar", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Inténtalo de nuevo.") }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cerrar") { inputFocused = false; dismiss() }
                    .foregroundColor(LenaraColors.accent)
            }
            ToolbarItem(placement: .principal) {
                Text("Lenara")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(LenaraColors.textPrimary)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Eliminar conversación", role: .destructive) { showingClearConfirmation = true }
                } label: { Image(systemName: "ellipsis") }
                .disabled(messages.isEmpty)
            }
        }
        .confirmationDialog("Se eliminará el historial de conversación de este dispositivo.", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("Eliminar conversación", role: .destructive) {
                messages.forEach { modelContext.delete($0) }
                do { try modelContext.save() } catch { modelContext.rollback(); errorMessage = error.localizedDescription }
            }
            Button("Cancelar", role: .cancel) {}
        }
        }
        .coordinateSpace(name: "chatRoot")
        .contentShape(Rectangle())
        .simultaneousGesture(SpatialTapGesture().onEnded { tap in
            if !inputFrame.insetBy(dx: -4, dy: -4).contains(tap.location) { inputFocused = false }
        })
    }

    private func strongAlarmBanner(_ reminder: Reminder) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "alarm.waves.left.and.right.fill")
                .foregroundStyle(LenaraColors.error)
            VStack(alignment: .leading, spacing: 3) {
                Text("Alarma fuerte activa")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LenaraColors.textPrimary)
                Text(reminder.title)
                    .font(.caption)
                    .foregroundStyle(LenaraColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button("Detener alarma fuerte") { stopStrongAlarm(reminder) }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(LenaraColors.error, in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(LenaraColors.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(LenaraColors.divider).frame(height: 1) }
    }

    private func stopStrongAlarm(_ reminder: Reminder) {
        LocalNotificationManager.shared.acknowledge(reminder)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = "No se pudo detener la alarma fuerte. Inténtalo otra vez."
        }
    }

    private var startScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.system(size: 48))
                .foregroundColor(LenaraColors.accent.opacity(0.6))

            Text("Hola, soy Lenara")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(LenaraColors.textPrimary)

            Text("Puedo ayudarte a guardar ideas, crear recordatorios y organizar tus tareas. Todo se procesa localmente.")
                .font(.body)
                .foregroundColor(LenaraColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }

    private func messageBubble(_ message: ConversationMessage) -> some View {
        let isUser = message.isUser

        return HStack {
            if isUser {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(visibleText(for: message))
                        .font(.body)
                        .foregroundColor(LenaraColors.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(LenaraColors.userBubble)
                        .cornerRadius(18)

                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundColor(LenaraColors.textTertiary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Lenara")
                            .font(.caption2)
                            .foregroundColor(LenaraColors.accent)
                        Spacer()
                    }

                    Text(visibleText(for: message))
                        .font(.body)
                        .foregroundColor(LenaraColors.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(LenaraColors.surface)
                        .cornerRadius(18)

                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundColor(LenaraColors.textTertiary)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            Button { showingVoiceCapture = true } label: {
                Image(systemName: "mic")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(LenaraColors.accent)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dictar mensaje")

            TextField("Escribe un mensaje...", text: $inputText)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .background(GeometryReader { geometry in
                    Color.clear
                        .onAppear { inputFrame = geometry.frame(in: .named("chatRoot")) }
                        .onChange(of: geometry.frame(in: .named("chatRoot"))) { _, frame in inputFrame = frame }
                })
                .padding(12)
                .background(LenaraColors.surface)
                .cornerRadius(22)
                .foregroundColor(LenaraColors.textPrimary)

            Button {
                sendMessage()
            } label: {
                Image(systemName: isProcessing ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isProcessing
                        ? LenaraColors.textTertiary
                        : LenaraColors.accent)
                    .opacity(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isProcessing ? 0.5 : 1.0)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isProcessing)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(LenaraColors.surface)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { inputFocused = false }
                    .tint(LenaraColors.logoMint)
            }
        }
    }

    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isProcessing else { return }

        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""
        inputFocused = false
        isProcessing = true
        _Concurrency.Task { @MainActor in
            do {
                modelContext.insert(ConversationMessage(content: text, isUser: true))
                let response = try await processMessage(text)
                let reply = ConversationMessage(content: response, isUser: false)
                modelContext.insert(reply)
                animatedAssistantID = reply.id
                animatedAssistantText = ""
                try modelContext.save()
                await animateAssistantResponse(response, messageID: reply.id)
            } catch {
                modelContext.rollback()
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }

    private func visibleText(for message: ConversationMessage) -> String {
        message.id == animatedAssistantID ? animatedAssistantText : message.content
    }

    @MainActor
    private func animateAssistantResponse(_ response: String, messageID: UUID) async {
        let characters = Array(response)
        var visibleCount = 0
        while visibleCount < characters.count {
            guard animatedAssistantID == messageID else { return }
            visibleCount = min(visibleCount + 2, characters.count)
            animatedAssistantText = String(characters.prefix(visibleCount))
            try? await _Concurrency.Task.sleep(nanoseconds: 7_000_000)
        }
        animatedAssistantID = nil
        animatedAssistantText = ""
    }

    private func processMessage(_ text: String) async throws -> String {
        var intent = intentParser.parse(text)
        if intent.action == .unknown, let request = pendingReminderRequest, let pendingReminderTitle {
            let original = intentParser.parse(request)
            let strongSuffix = original.isStrongAlarm ? " alarma fuerte" : ""
            var contextual = intentParser.parse("Recuérdame \(pendingReminderTitle) \(text)\(strongSuffix)")
            if contextual.date == nil || (original.isRepeating == true && contextual.isRepeating != true) {
                contextual = intentParser.parse(request + " " + text)
            }
            if contextual.date == nil {
                let qualifier = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                if ["manana", "tarde", "noche", "am", "pm"].contains(where: qualifier.contains) {
                    // A short answer resolves all unqualified times while preserving weekdays and alarm type.
                    let suffix = qualifier.contains("tarde") || qualifier.contains("noche") || qualifier.contains("pm") ? " pm" : " am"
                    let expanded = request.replacingOccurrences(of: #"(a las?\s+(?:1[0-2]|[1-9]|una|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce))(?=\s*(?:,|y|todos|cada|$))"#, with: "$1" + suffix, options: [.regularExpression, .caseInsensitive])
                    contextual = intentParser.parse(expanded)
                }
            }
            if contextual.date != nil { intent = contextual }
        }

        switch intent.action {
        case .createReminder:
            if let title = intent.title {
                guard let date = intent.date else {
                    pendingReminderTitle = title
                    pendingReminderRequest = text
                    if let question = intent.clarification { return question }
                    return "¿Qué día y a qué hora? Por ejemplo: «hoy a las seis de la tarde» o «mañana a las nueve de la mañana»."
                }
                let existing = try modelContext.fetch(FetchDescriptor<Reminder>())
                if existing.contains(where: {
                    $0.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                        && abs($0.date.timeIntervalSince(date)) < 60
                        && $0.scheduleSlots == intent.recurrenceSlots
                        && $0.isStrongAlarm == intent.isStrongAlarm
                        && !$0.isCompleted
                }) {
                    pendingReminderTitle = nil
                    return "Ese recordatorio ya está guardado para el \(dateFormatter.string(from: date))."
                }
                let reminder = Reminder(title: title, date: date, repeats: intent.isRepeating ?? false, isStrongAlarm: intent.isStrongAlarm)
                reminder.scheduleSlots = intent.recurrenceSlots
                do {
                    try await LocalNotificationManager.shared.scheduleReminder(reminder)
                    modelContext.insert(reminder)
                    try modelContext.save()
                } catch {
                    LocalNotificationManager.shared.cancelReminder(reminder)
                    if reminder.modelContext != nil { modelContext.delete(reminder) }
                    try? modelContext.save()
                    return "No pude programar el recordatorio. \(error.localizedDescription)"
                }
                pendingReminderTitle = nil
                let formattedDate = dateFormatter.string(from: date)
                pendingReminderRequest = nil
                let confirmation = reminder.repeats
                    ? "Recordatorio creado: \(title).\n\(reminder.scheduleDescription)"
                    : "Recordatorio creado para el \(formattedDate)"
                return confirmation + (reminder.isStrongAlarm ? "\nUsaré el sonido fuerte. Con Lenara cerrada será un aviso sonoro; al abrirlo podrás detenerlo o posponerlo." : "")
            } else {
                return "¿Qué quieres que te recuerde?"
            }

        case .createMemory:
            if let title = intent.title {
                let memory = Memory(
                    title: title,
                    content: intent.content ?? "",
                    category: intent.category,
                    tags: intent.tags ?? []
                )
                modelContext.insert(memory)
                try modelContext.save()
                return "He guardado: \(title)"
            } else {
                return "¿Qué quieres que guarde?"
            }

        case .createTask:
            if let title = intent.title {
                let task = Task(title: title, dueDate: intent.date)
                modelContext.insert(task)
                try modelContext.save()
                return "Tarea creada: \(title)"
            } else {
                return "¿Qué tarea quieres crear?"
            }

        case .searchMemory:
            let results = MemoryService().searchMemory(in: modelContext, query: intent.title ?? "")
            if results.isEmpty {
                return "No encontré recuerdos sobre eso."
            } else {
                let titles = results.map { $0.title }.joined(separator: ", ")
                return "Encontré \(results.count) recuerdo(s): \(titles)"
            }

        case .listTasks:
            let tasks = TaskService().fetchAll(in: modelContext)
            let pending = tasks.filter { $0.status == .pending }
            if pending.isEmpty {
                return "No tienes tareas pendientes."
            } else {
                let titles = pending.map { $0.title }.joined(separator: ", ")
                return "Tienes \(pending.count) tarea(s) pendiente(s): \(titles)"
            }

        case .listReminders:
            let reminders = ReminderService().fetchAll(in: modelContext)
            let upcoming = reminders.filter { ($0.repeats || $0.date > .now || ($0.snoozedUntil ?? .distantPast) > .now) && !$0.isCompleted }
            if upcoming.isEmpty {
                return "No tienes recordatorios próximos."
            } else {
                let titles = upcoming.map { $0.title }.joined(separator: ", ")
                return "Tienes \(upcoming.count) recordatorio(s) próximo(s): \(titles)"
            }

        case .strongAlarm:
            return "¿Qué quieres que te recuerde y cuándo? Por ejemplo: «Recuérdame apagar el horno dentro de diez minutos con alarma fuerte». El sonido continúa con Lenara abierta; con la app cerrada será un aviso sonoro."

        case .deleteItem:
            return "¿Qué quieres eliminar? Dime el título exacto."

        case .greeting:
            let name = userName.isEmpty ? "" : ", \(userName)"
            return "Hola\(name). ¿En qué puedo ayudarte?"

        case .help:
            return "Puedo ayudarte a:\n• Guardar ideas y recuerdos (\"Guarda esta idea: ...\")\n• Crear recordatorios (\"Recuérdame mañana a las 7\")\n• Crear tareas (\"Crear tarea: comprar leche\")\n• Buscar recuerdos (\"Buscar sobre proyectos\")\n• Ver tus tareas y recordatorios"

        case .unknown:
            if let modelURL = LocalModelManager.shared.fileURL(for: LocalModelManager.shared.selectedID) {
                do {
                    let generated = try await LocalLlamaEngine.shared.respond(
                        to: text,
                        modelURL: modelURL,
                        modelID: LocalModelManager.shared.selectedID
                    )
                    return safeModelReply(generated, for: text)
                } catch {
                    return "No pude usar el modelo local. Tus notas, tareas y recordatorios siguen disponibles. \(error.localizedDescription)"
                }
            }
            return "Puedo guardar recuerdos, crear tareas o recordatorios y buscar en lo guardado. Dime qué quieres hacer."
        }
    }

    private func safeModelReply(_ reply: String, for request: String) -> String {
        let wantsCode = ["código", "codigo", "programa", "script", "swift", "python"].contains {
            request.localizedCaseInsensitiveContains($0)
        }
        let clean = reply
            .replacingOccurrences(of: #"<\|(?:im_start|im_end|assistant|user|system)\|>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let looksLikeCode = clean.contains("```") || clean.hasPrefix("import Swift") || clean.hasPrefix("{\n  \"")
        guard !looksLikeCode || wantsCode else {
            return "No pude interpretar eso con suficiente seguridad. Puedes pedirme que guarde una idea, cree una tarea o programe un recordatorio con fecha y hora."
        }
        return clean.isEmpty ? "No pude preparar una respuesta. Inténtalo de otra forma." : clean
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d 'de' MMMM 'a las' h:mm a"
        formatter.locale = Locale(identifier: "es_PE")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }
}
