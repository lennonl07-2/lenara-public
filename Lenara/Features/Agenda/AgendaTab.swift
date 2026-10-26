import SwiftUI
import SwiftData

// MARK: - Agenda Tab (Tasks + Reminders)
struct AgendaTab: View {
    var body: some View {
        NavigationStack { RemindersTab() }
    }
}

// MARK: - Reminders Tab
struct RemindersTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showAdd = false
    @State private var editingReminder: Reminder?
    @State private var showingClearPastConfirmation = false
    @State private var errorMessage: String?

    private var reminders: [Reminder] {
        do {
            let descriptor = SortDescriptor(\Reminder.date, order: .forward)
            return try modelContext.fetch(FetchDescriptor<Reminder>(sortBy: [descriptor]))
        } catch {
            return []
        }
    }

    private var upcomingReminders: [Reminder] { reminders.filter { !$0.isCompleted && ($0.repeats || $0.displayDate >= .now) } }
    private var pastReminders: [Reminder] { reminders.filter { $0.isCompleted || (!$0.repeats && $0.displayDate < .now) } }

    var body: some View {
        List {
            if upcomingReminders.isEmpty && pastReminders.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bell").font(.system(size: 34)).foregroundStyle(LenaraColors.textTertiary)
                    Text("Sin recordatorios").font(.headline).foregroundStyle(LenaraColors.textPrimary)
                    Text("Los recordatorios que crees aparecerán aquí.").font(.subheadline).foregroundStyle(LenaraColors.textSecondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 38).listRowBackground(LenaraColors.background)
            } else {
                if !upcomingReminders.isEmpty {
                    Section("Próximos") {
                        ForEach(upcomingReminders) { reminder in reminderRow(reminder) }
                    }
                }
                if !pastReminders.isEmpty {
                    Section {
                        ForEach(pastReminders) { reminder in reminderRow(reminder) }
                    } header: { Text("Pasados y completados") }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(LenaraColors.background)
        .foregroundStyle(LenaraColors.textPrimary)
        .navigationTitle("Recordatorios")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: {
                    Label("Nuevo", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Limpiar pasados", systemImage: "trash") { showingClearPastConfirmation = true }
                    .disabled(!reminders.contains(where: { $0.date < .now }))
            }
        }
        .sheet(isPresented: $showAdd) {
            AddReminderSheet()
        }
        .sheet(item: $editingReminder) { reminder in AddReminderSheet(reminder: reminder) }
        .confirmationDialog("Eliminar todos los recordatorios vencidos o completados", isPresented: $showingClearPastConfirmation, titleVisibility: .visible) {
            Button("Limpiar recordatorios pasados", role: .destructive) { clearPastReminders() }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Agenda", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Aceptar", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func reminderRow(_ reminder: Reminder) -> some View {
        HStack(spacing: 12) {
            Button {
                reminder.isCompleted.toggle()
                if reminder.isCompleted {
                    LocalNotificationManager.shared.cancelReminder(reminder)
                } else if reminder.date > .now {
                    _Concurrency.Task { @MainActor in
                        do { try await LocalNotificationManager.shared.scheduleReminder(reminder); try modelContext.save() }
                        catch { errorMessage = "No se pudo reactivar el aviso. \(error.localizedDescription)" }
                    }
                }
                do { try modelContext.save() } catch { modelContext.rollback(); errorMessage = "No se pudo actualizar el recordatorio." }
            } label: {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(reminder.isCompleted ? LenaraColors.success : LenaraColors.textTertiary)
                    .font(.system(size: 21, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .background(LenaraColors.logoMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(reminder.isCompleted ? "Reabrir \(reminder.title)" : "Completar \(reminder.title)")

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.body)
                    .foregroundColor(reminder.isCompleted ? LenaraColors.textTertiary : LenaraColors.textPrimary)
                    .strikethrough(reminder.isCompleted)

                Text(reminder.displayDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(LenaraColors.textSecondary)
            }

            if reminder.repeats { Image(systemName: "repeat").font(.caption).foregroundStyle(LenaraColors.accent) }
            Button { editingReminder = reminder } label: { Image(systemName: "pencil").frame(width: 38, height: 42) }
                .buttonStyle(.borderless).accessibilityLabel("Editar \(reminder.title)")
            Button(role: .destructive) { deleteReminder(reminder) } label: { Image(systemName: "trash").frame(width: 38, height: 42) }
                .buttonStyle(.borderless).accessibilityLabel("Eliminar \(reminder.title)")
        }
        .listRowBackground(LenaraColors.surface)
        .listRowSeparatorTint(LenaraColors.divider)
    }

    private func deleteReminder(_ reminder: Reminder) {
        LocalNotificationManager.shared.cancelReminder(reminder)
        modelContext.delete(reminder)
        do { try modelContext.save() } catch { modelContext.rollback(); errorMessage = "No se pudo eliminar el recordatorio." }
    }

    private func clearPastReminders() {
        let past = reminders.filter { $0.isCompleted || (!$0.repeats && $0.date < .now) }
        past.forEach { LocalNotificationManager.shared.cancelReminder($0); modelContext.delete($0) }
        do { try modelContext.save() } catch { modelContext.rollback(); errorMessage = "No se pudieron limpiar los recordatorios pasados." }
    }
}

// MARK: - Tasks Tab
struct TasksTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showAdd = false
    @State private var filterStatus: TaskStatus? = nil

    private var tasks: [Task] {
        do {
            let descriptor = SortDescriptor(\Task.dueDate, order: .forward)
            return try modelContext.fetch(FetchDescriptor<Task>(sortBy: [descriptor]))
        } catch {
            return []
        }
    }

    private var filteredTasks: [Task] {
        guard let status = filterStatus else { return tasks }
        return tasks.filter { $0.status == status }
    }

    var body: some View {
        List {
            if filteredTasks.isEmpty {
                Text(filterStatus == nil ? "No hay tareas" : "No hay tareas \(filterStatus?.rawValue ?? "")")
                    .foregroundColor(LenaraColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(filteredTasks) { task in
                    taskRow(task)
                }
                .onDelete(perform: deleteTasks)
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus")
                        .foregroundColor(LenaraColors.accent)
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button("Todas") { filterStatus = nil }
                    Button("Pendientes") { filterStatus = .pending }
                    Button("Completadas") { filterStatus = .completed }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundColor(LenaraColors.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddTaskSheet()
        }
    }

    private func taskRow(_ task: Task) -> some View {
        HStack {
            Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundColor(task.status == .completed ? LenaraColors.success : LenaraColors.textTertiary)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body)
                    .foregroundColor(task.status == .completed ? LenaraColors.textTertiary : LenaraColors.textPrimary)
                    .strikethrough(task.status == .completed)

                if let dueDate = task.dueDate {
                    Text(dueDate, style: .date)
                        .font(.caption)
                        .foregroundColor((task.dueDate ?? Date()) < Date() && task.status != .completed ? LenaraColors.error : LenaraColors.textSecondary)
                }
            }

            Spacer()

            if task.priority == .high {
                Image(systemName: "flag.fill")
                    .font(.caption)
                    .foregroundColor(LenaraColors.warning)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                task.toggleStatus()
                do { try modelContext.save() } catch { modelContext.rollback() }
            }
        }
    }

    private func deleteTasks(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredTasks[index])
        }
    }
}

struct TaskManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Task.createdAt, order: .reverse) private var tasks: [Task]
    @State private var showNewTask = false
    @State private var editingTask: Task?
    @State private var showingClearHistory = false
    @State private var errorMessage: String?

    private var pendingTasks: [Task] { tasks.filter { $0.status == .pending } }
    private var completedTasks: [Task] { tasks.filter { $0.status == .completed } }

    var body: some View {
        NavigationStack {
            List {
                Section("Pendientes") {
                    if pendingTasks.isEmpty {
                        Text("No tienes tareas pendientes.")
                            .foregroundStyle(LenaraColors.textSecondary)
                    } else {
                        ForEach(pendingTasks) { task in taskRow(task, completed: false) }
                    }
                }

                Section {
                    if completedTasks.isEmpty {
                        Text("Todavía no hay tareas completadas.")
                            .foregroundStyle(LenaraColors.textSecondary)
                    } else {
                        ForEach(completedTasks) { task in taskRow(task, completed: true) }
                    }
                } header: {
                    Text("Historial de tareas")
                } footer: {
                    if !completedTasks.isEmpty {
                        Button("Borrar historial de tareas", role: .destructive) {
                            showingClearHistory = true
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(LenaraColors.background)
            .navigationTitle("Tareas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showNewTask = true } label: {
                        Label("Nueva tarea", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewTask) {
                AddTaskSheet().preferredColorScheme(.dark)
            }
            .sheet(item: $editingTask) { task in
                AddTaskSheet(task: task).preferredColorScheme(.dark)
            }
            .confirmationDialog("Eliminar todas las tareas completadas del historial", isPresented: $showingClearHistory, titleVisibility: .visible) {
                Button("Borrar historial", role: .destructive) { clearHistory() }
                Button("Cancelar", role: .cancel) {}
            }
            .alert("Tareas", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Aceptar", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func taskRow(_ task: Task, completed: Bool) -> some View {
        HStack(spacing: 10) {
            Button { toggle(task) } label: {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(completed ? LenaraColors.success : LenaraColors.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(completed ? "Reabrir tarea" : "Completar tarea")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(completed ? LenaraColors.textTertiary : LenaraColors.textPrimary)
                    .strikethrough(completed)
                let itemCount = TaskChecklistCodec.decode(task.detail).items.count
                if itemCount > 0 {
                    Text("\(itemCount) pendientes")
                        .font(.caption)
                        .foregroundStyle(LenaraColors.textSecondary)
                } else if let dueDate = task.dueDate {
                    Text(dueDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(LenaraColors.textSecondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { editingTask = task }

            Spacer(minLength: 4)

            Button { editingTask = task } label: {
                Image(systemName: "pencil").foregroundStyle(LenaraColors.logoMint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Editar \(task.title)")

            Button(role: .destructive) { delete(task) } label: {
                Image(systemName: "trash").foregroundStyle(LenaraColors.error)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Eliminar \(task.title)")
        }
        .padding(.vertical, 4)
        .listRowBackground(LenaraColors.surface)
    }

    private func toggle(_ task: Task) {
        task.toggleStatus()
        saveChanges(message: "No se pudo actualizar la tarea.")
    }

    private func delete(_ task: Task) {
        modelContext.delete(task)
        saveChanges(message: "No se pudo eliminar la tarea.")
    }

    private func clearHistory() {
        completedTasks.forEach(modelContext.delete)
        saveChanges(message: "No se pudo borrar el historial.")
    }

    private func saveChanges(message: String) {
        do { try modelContext.save() }
        catch { modelContext.rollback(); errorMessage = message }
    }
}

// MARK: - Add Reminder Sheet
struct AddReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var title: String
    @State private var date: Date
    @State private var repeats: Bool
    @State private var strongAlarm: Bool
    @State private var slots: [ReminderSlot]
    @State private var errorMessage: String?
    @State private var isSaving = false
    private let existingReminder: Reminder?

    init(reminder: Reminder? = nil) {
        existingReminder = reminder
        _title = State(initialValue: reminder?.title ?? "")
        _date = State(initialValue: reminder?.nextScheduledDate() ?? Date.now.addingTimeInterval(300))
        _repeats = State(initialValue: reminder?.repeats ?? false)
        _strongAlarm = State(initialValue: reminder?.isStrongAlarm ?? false)
        _slots = State(initialValue: reminder?.scheduleSlots.isEmpty == false ? reminder!.scheduleSlots : [ReminderSlot(hour: 9, minute: 0)])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Título") { TextField("Título del recordatorio", text: $title) }
                Section {
                    Toggle("Repetir", isOn: $repeats)
                    if repeats {
                        ForEach(slots.indices, id: \.self) { index in
                            VStack(alignment: .leading) {
                                HStack {
                                    Picker("Día", selection: Binding(get: { slots[index].weekday ?? 0 }, set: { slots[index].weekday = $0 == 0 ? nil : $0 })) {
                                        Text("Todos los días").tag(0)
                                        ForEach(1...7, id: \.self) { day in
                                            Text(["", "Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"][day]).tag(day)
                                        }
                                    }
                                    if slots.count > 1 {
                                        Button(role: .destructive) { slots.remove(at: index) } label: {
                                            Image(systemName: "minus.circle").frame(width: 44, height: 44)
                                        }.buttonStyle(.borderless).accessibilityLabel("Quitar horario")
                                    }
                                }
                                DatePicker("Hora", selection: timeBinding(index), displayedComponents: .hourAndMinute)
                            }
                        }
                        Button { slots.append(ReminderSlot(hour: 18, minute: 0)) } label: { Label("Añadir horario", systemImage: "plus.circle") }
                            .disabled(slots.count >= 32)
                    } else {
                        DatePicker("Fecha y hora", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    }
                } header: { Text("Cuándo avisarte") }
                Section {
                    Toggle("Sonido de alarma fuerte", isOn: $strongAlarm)
                } footer: {
                    if strongAlarm { Text("Con Lenara abierta, el sonido continúa hasta detenerlo. Con la app cerrada, recibirás un aviso sonoro sujeto a los ajustes de iOS.") }
                }
            }
            .navigationTitle(existingReminder == nil ? "Nuevo recordatorio" : "Editar recordatorio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { saveReminder() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .alert("No se pudo programar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Aceptar", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func timeBinding(_ index: Int) -> Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: slots[index].hour, minute: slots[index].minute, second: 0, of: .now) ?? .now },
                set: { slots[index].hour = Calendar.current.component(.hour, from: $0); slots[index].minute = Calendar.current.component(.minute, from: $0) })
    }

    private func saveReminder() {
        let uniqueSlots = Array(Set(slots)).sorted { $0.id < $1.id }
        let nextDate = repeats ? uniqueSlots.compactMap { $0.nextDate(after: .now) }.min() : date
        guard let nextDate, nextDate > .now else { errorMessage = "Elige una fecha futura."; return }
        isSaving = true
        _Concurrency.Task { @MainActor in
            let reminder = existingReminder ?? Reminder(title: "", date: nextDate)
            let oldTitle = reminder.title, oldDate = reminder.date, oldSlots = reminder.scheduleSlots
            let oldStrong = reminder.isStrongAlarm, oldCompleted = reminder.isCompleted
            let oldSnooze = reminder.snoozedUntil, oldAcknowledged = reminder.acknowledgedAt
            reminder.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            reminder.date = nextDate
            reminder.scheduleSlots = repeats ? uniqueSlots : []
            reminder.isStrongAlarm = strongAlarm
            reminder.isCompleted = false
            reminder.snoozedUntil = nil
            reminder.acknowledgedAt = nil
            reminder.updatedAt = .now
            var didSchedule = false
            do {
                try await LocalNotificationManager.shared.scheduleReminder(reminder)
                didSchedule = true
                if existingReminder == nil { modelContext.insert(reminder) }
                try modelContext.save()
                dismiss()
            } catch {
                // Scheduling restores the old pending requests if it fails; preserve the old model too.
                if didSchedule { LocalNotificationManager.shared.cancelReminder(reminder) }
                reminder.title = oldTitle; reminder.date = oldDate; reminder.scheduleSlots = oldSlots
                reminder.isStrongAlarm = oldStrong; reminder.isCompleted = oldCompleted
                reminder.snoozedUntil = oldSnooze; reminder.acknowledgedAt = oldAcknowledged
                if existingReminder == nil {
                    LocalNotificationManager.shared.cancelReminder(reminder)
                    if reminder.modelContext != nil { modelContext.delete(reminder) }
                } else if !oldCompleted && (oldDate > .now || !oldSlots.isEmpty) {
                    try? await LocalNotificationManager.shared.scheduleReminder(reminder)
                }
                try? modelContext.save()
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Add Task Sheet
struct AddTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var title: String
    @State private var description: String
    @State private var checklistItems: [ChecklistDraft]
    @State private var dueDate: Date?
    @State private var saveError: String?
    @State private var voiceTarget: TaskVoiceTarget?
    @State private var isChecklistVoiceActive = false
    @State private var isChecklistVoiceStopping = false
    @State private var isProcessingChecklistCommand = false
    @State private var checklistVoiceMessage: String?
    @State private var checklistVoiceMessageIsError = false
    @State private var livePendingTranscript = ""
    @StateObject private var checklistVoice = VoiceCaptureModel()
    @FocusState private var titleFieldFocused: Bool
    private let existingTask: Task?

    init(task: Task? = nil) {
        existingTask = task
        let payload = TaskChecklistCodec.decode(task?.detail)
        _title = State(initialValue: task?.title ?? "")
        _description = State(initialValue: payload.description)
        _checklistItems = State(initialValue: payload.items.isEmpty ? [ChecklistDraft()] : payload.items.map(ChecklistDraft.init(item:)))
        _dueDate = State(initialValue: task?.dueDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Título") {
                    HStack(spacing: 10) {
                        Button { voiceTarget = .title } label: {
                            Image(systemName: "mic.fill")
                                .foregroundStyle(LenaraColors.logoMint)
                                .font(.system(size: 21, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .background(LenaraColors.logoMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .accessibilityLabel("Dictar título por voz")
                        TextField("Título", text: $title)
                            .focused($titleFieldFocused)
                    }
                }

                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Button { voiceTarget = .notes } label: {
                            Image(systemName: "mic.fill")
                                .foregroundStyle(LenaraColors.logoMint)
                                .font(.system(size: 21, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .background(LenaraColors.logoMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .accessibilityLabel("Dictar notas por voz")
                        TextEditor(text: $description)
                            .frame(minHeight: 80)
                    }
                } header: { Text("Notas") }

                Section {
                    Button(action: toggleChecklistVoice) {
                        Label(
                            isChecklistVoiceActive ? "Detener dictado de pendientes" : "Dictar pendientes",
                            systemImage: isChecklistVoiceActive ? "stop.circle.fill" : "mic.circle.fill"
                        )
                        .font(.system(size: 18, weight: .semibold))
                        .frame(minHeight: 48)
                        .foregroundStyle(isChecklistVoiceActive ? LenaraColors.warning : LenaraColors.logoMint)
                    }
                    .disabled(checklistVoice.isWorking && !checklistVoice.isRecording)
                    ForEach($checklistItems) { $item in
                        HStack(spacing: 10) {
                            Image(systemName: "circle").foregroundStyle(LenaraColors.textTertiary)
                            TextField("Escribe un paso", text: $item.title)
                            Button(role: .destructive) {
                                checklistItems.removeAll { $0.id == item.id }
                                if checklistItems.isEmpty { checklistItems.append(ChecklistDraft()) }
                            } label: { Image(systemName: "minus.circle").font(.title3).frame(width: 44, height: 44) }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Quitar paso")
                        }
                    }
                    if isChecklistVoiceActive && !livePendingTranscript.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "waveform")
                                .foregroundStyle(LenaraColors.logoMint)
                            Text(livePendingTranscript)
                                .foregroundStyle(LenaraColors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.body)
                        .accessibilityLabel("Pendiente dictado: \(livePendingTranscript)")
                    }
                    Button { checklistItems.append(ChecklistDraft()) } label: {
                        Label("Añadir paso", systemImage: "plus.circle")
                    }
                    if isChecklistVoiceActive {
                        Label(
                            checklistVoice.isWorking ? "Procesando voz…" : "Di un pendiente y luego NEXT. Di finish para terminar.",
                            systemImage: checklistVoice.isRecording ? "waveform" : "mic"
                        )
                        .font(.caption)
                        .foregroundStyle(LenaraColors.textSecondary)
                    }
                    if let checklistVoiceMessage {
                        Text(checklistVoiceMessage)
                            .font(.caption)
                            .foregroundStyle(checklistVoiceMessageIsError ? LenaraColors.error : LenaraColors.textSecondary)
                    }
                } header: {
                    Text("Pendientes")
                }

                Section("Fecha límite") {
                    if dueDate != nil {
                        DatePicker("Fecha", selection: Binding(get: { dueDate ?? Date() }, set: { dueDate = $0 }), displayedComponents: [.date])
                    } else {
                        Button("Establecer fecha") { dueDate = Date() }
                            .foregroundColor(LenaraColors.accent)
                    }
                }

            }
            .navigationTitle(existingTask == nil ? "Nueva tarea" : "Editar tarea")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { saveTask() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(item: $voiceTarget) { target in
                VoiceCaptureSheet(autoStart: true) { dictatedText in
                    switch target {
                    case .title:
                        title = dictatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    case .notes:
                        let existingNotes = description.trimmingCharacters(in: .whitespacesAndNewlines)
                        description = existingNotes.isEmpty ? dictatedText : existingNotes + "\n" + dictatedText
                    }
                }
                .preferredColorScheme(.dark)
            }
            .onChange(of: checklistVoice.transcript) { _, transcript in
                processChecklistVoice(transcript)
            }
            .onChange(of: checklistVoice.didFinishTranscription) { _, finished in
                guard finished, isChecklistVoiceStopping else { return }
                appendVoicePending(mostCompleteVoiceText(checklistVoice.transcript, livePendingTranscript))
                finishChecklistVoice(message: "Dictado terminado.")
            }
            .onChange(of: checklistVoice.errorMessage) { _, message in
                guard let message else { return }
                checklistVoiceMessage = message
                checklistVoiceMessageIsError = true
                isChecklistVoiceActive = false
                isChecklistVoiceStopping = false
                isProcessingChecklistCommand = false
                livePendingTranscript = ""
            }
            .onDisappear { checklistVoice.cancel() }
        }
        .alert("No se pudo guardar", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("Aceptar", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    private func saveTask() {
        let detail = TaskChecklistCodec.encode(
            description: description,
            items: checklistItems.map {
                WidgetChecklistItem(id: $0.id, title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines), isCompleted: $0.isCompleted)
            }
        )
        if let existingTask {
            existingTask.title = title.trimmingCharacters(in: .whitespaces)
            existingTask.detail = detail
            existingTask.dueDate = dueDate
            let items = checklistItems.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !items.isEmpty {
                existingTask.status = items.allSatisfy(\.isCompleted) ? .completed : .pending
                existingTask.completedAt = existingTask.status == .completed ? .now : nil
            }
        } else {
            modelContext.insert(Task(
                title: title.trimmingCharacters(in: .whitespaces),
                detail: detail,
                dueDate: dueDate
            ))
        }
        do { try modelContext.save(); dismiss() }
        catch { modelContext.rollback(); saveError = error.localizedDescription }
    }

    private func toggleChecklistVoice() {
        checklistVoiceMessage = nil
        checklistVoiceMessageIsError = false
        if checklistVoice.isRecording {
            isChecklistVoiceStopping = true
            checklistVoice.stop()
        } else {
            isChecklistVoiceActive = true
            isChecklistVoiceStopping = false
            livePendingTranscript = ""
            checklistItems.removeAll { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            _Concurrency.Task { await checklistVoice.start() }
        }
    }

    private func processChecklistVoice(_ transcript: String) {
        guard isChecklistVoiceActive, !isChecklistVoiceStopping, !isProcessingChecklistCommand else { return }
        let words = transcript.split(whereSeparator: \.isWhitespace).map(String.init)
        let finalWord = words.last?
            .trimmingCharacters(in: .punctuationCharacters)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let finishCommands = ["finish", "finished", "terminar", "termina", "finalizar", "finaliza", "final"]
        let isControlWord = (["next", "siguiente"] + finishCommands).contains(finalWord ?? "")
        let textBeforeCommand = words.dropLast().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if isControlWord {
            // Some Speech updates contain only the command word. Keep the
            // previous partial transcript until we commit the pending.
            if !textBeforeCommand.isEmpty { livePendingTranscript = textBeforeCommand }
        } else {
            livePendingTranscript = transcript
        }

        guard let lastWord = words.last else { return }
        let command = lastWord
            .trimmingCharacters(in: .punctuationCharacters)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let isNext = ["next", "siguiente"].contains(command)
        let isFinish = finishCommands.contains(command)
        guard isNext || isFinish else { return }

        isProcessingChecklistCommand = true
        let recognizedPending = isFinish ? removingTrailingFinishMarker(textBeforeCommand) : textBeforeCommand
        let bufferedPending = isFinish ? removingTrailingFinishMarker(livePendingTranscript) : livePendingTranscript
        appendVoicePending(mostCompleteVoiceText(recognizedPending, bufferedPending))
        livePendingTranscript = ""
        checklistVoice.cancel()

        if isFinish {
            finishChecklistVoice(message: "Dictado terminado.")
        } else {
            checklistVoiceMessage = "Pendiente guardado. Di el siguiente y luego NEXT."
            checklistVoiceMessageIsError = false
            _Concurrency.Task {
                try? await _Concurrency.Task.sleep(for: .milliseconds(300))
                guard isChecklistVoiceActive else { return }
                isProcessingChecklistCommand = false
                await checklistVoice.start()
            }
        }
    }

    private func appendVoicePending(_ text: String) {
        let pending = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pending.isEmpty else { return }
        checklistItems.append(ChecklistDraft(title: pending))
    }

    private func mostCompleteVoiceText(_ first: String, _ second: String) -> String {
        let first = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = second.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstWordCount = first.split(whereSeparator: \.isWhitespace).count
        let secondWordCount = second.split(whereSeparator: \.isWhitespace).count
        return secondWordCount > firstWordCount ? second : first
    }

    private func removingTrailingFinishMarker(_ text: String) -> String {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let lastWord = words.last else { return text }
        let normalizedLastWord = lastWord
            .trimmingCharacters(in: .punctuationCharacters)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        if ["finish", "finished", "terminar", "termina", "finalizar", "finaliza", "final"].contains(normalizedLastWord) {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }

    private func finishChecklistVoice(message: String) {
        isChecklistVoiceActive = false
        isChecklistVoiceStopping = false
        isProcessingChecklistCommand = false
        livePendingTranscript = ""
        checklistVoiceMessage = message
        checklistVoiceMessageIsError = false
        while checklistItems.count > 1,
              checklistItems.last?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            checklistItems.removeLast()
        }
    }
}

private enum TaskVoiceTarget: String, Identifiable {
    case title
    case notes

    var id: String { rawValue }
}

private struct ChecklistDraft: Identifiable {
    let id: String
    var title: String
    var isCompleted: Bool

    init(title: String = "", isCompleted: Bool = false) {
        id = UUID().uuidString
        self.title = title
        self.isCompleted = isCompleted
    }

    init(item: WidgetChecklistItem) {
        id = item.id
        title = item.title
        isCompleted = item.isCompleted
    }
}
