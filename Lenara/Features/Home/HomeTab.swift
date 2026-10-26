import SwiftUI
import SwiftData
import WidgetKit
import Combine
import UIKit

struct HomeTab: View {
    @Binding var createTaskFromWidget: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Reminder.date) private var storedReminders: [Reminder]
    @Query(sort: \Task.createdAt, order: .reverse) private var storedTasks: [Task]
    @State private var chatInput = ""
    @FocusState private var chatInputFocused: Bool
    @State private var showChat = false
    @State private var showVoice = false
    @State private var showAddReminder = false
    @State private var showTasksManager = false
    @State private var showWidgetTaskSelection = false
    @State private var clockNow = Date.now
    @State private var showPastReminders = false
    @State private var showClearPastRemindersConfirmation = false
    @State private var showAllPendingTasks = false
    @State private var editingReminder: Reminder?
    @State private var reminderError: String?
    @State private var showWidgetGuide = false
    @State private var missingPermissions: [LenaraPermission] = []
    @State private var hasUnrequestedPermissions = false
    @State private var requestingPermissions = false
    @AppStorage("lenara.userName") private var userName = ""

    init(createTaskFromWidget: Binding<Bool> = .constant(false)) {
        _createTaskFromWidget = createTaskFromWidget
    }

    private var upcomingReminders: [Reminder] {
        storedReminders.filter { !$0.isCompleted && ($0.repeats || $0.date > clockNow || ($0.snoozedUntil ?? .distantPast) > clockNow) }
    }
    private var latestReminder: Reminder? {
        (upcomingReminders + (activeStrongAlarm.map { [$0] } ?? []))
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }
    private var otherUpcomingReminders: [Reminder] {
        upcomingReminders
            .filter { $0.id != latestReminder?.id }
            .sorted { $0.createdAt > $1.createdAt }
    }
    private var activeStrongAlarm: Reminder? {
        storedReminders.first { $0.hasUnacknowledgedStrongOccurrence(at: clockNow) }
    }
    private var pendingTasks: [Task] {
        storedTasks.filter { $0.status == .pending }
    }
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: clockNow)
        if hour < 4 || hour >= 19 { return "Buenas noches," }
        if hour < 12 { return "Buenos días," }
        return "Buenas tardes,"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if let activeStrongAlarm { strongAlarmBanner(activeStrongAlarm) }
                    if !missingPermissions.isEmpty { permissionNotice }
                    latestReminderCard
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                    composer
                    tasksButton
                    remindersSection
                    if !pendingTasks.isEmpty { tasksSection }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .padding(.bottom, 30)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(LenaraBackground().ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showChat) { ChatSheet(initialText: chatInput).preferredColorScheme(.dark) }
            .sheet(isPresented: $showVoice) {
                VoiceCaptureSheet(autoStart: true) { dictatedText in
                    chatInput = dictatedText
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showChat = true }
                }
            }
            .sheet(isPresented: $showAddReminder) { AddReminderSheet().preferredColorScheme(.dark) }
            .sheet(isPresented: $showTasksManager) { TaskManagerSheet().preferredColorScheme(.dark) }
            .sheet(item: $editingReminder) { AddReminderSheet(reminder: $0).preferredColorScheme(.dark) }
            .sheet(isPresented: $showWidgetGuide) { WidgetsGuideSheet().preferredColorScheme(.dark) }
            .sheet(isPresented: $showWidgetTaskSelection) { WidgetTaskSelectionSheet().preferredColorScheme(.dark) }
            .onAppear {
                clockNow = .now
                syncWidgetChecklistFromStore()
                refreshPermissionStatus()
            }
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { date in
                clockNow = date
            }
            .onChange(of: createTaskFromWidget, initial: true) { _, requested in
                guard requested else { return }
                showWidgetTaskSelection = true
                createTaskFromWidget = false
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    clockNow = .now
                    syncWidgetChecklistFromStore()
                    refreshPermissionStatus()
                }
            }
            .onChange(of: widgetTaskSnapshot) { _, newValue in
                WidgetSharedStore.writeTasks(newValue)
                WidgetCenter.shared.reloadTimelines(ofKind: "LenaraChecklist")
            }
            .alert("Recordatorio", isPresented: Binding(get: { reminderError != nil }, set: { if !$0 { reminderError = nil } })) {
                Button("Aceptar", role: .cancel) { reminderError = nil }
            } message: { Text(reminderError ?? "") }
            .confirmationDialog("Eliminar todos los recordatorios pasados", isPresented: $showClearPastRemindersConfirmation, titleVisibility: .visible) {
                Button("Eliminar todos los pasados", role: .destructive) { deleteAllPastReminders() }
                Button("Cancelar", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
    }

    private var latestReminderCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Último recordatorio", systemImage: "bell.badge.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LenaraColors.logoMint)
            if let latestReminder {
                Text(latestReminder.title)
                    .onTapGesture { openReminder(latestReminder) }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LenaraColors.textPrimary)
                    .lineLimit(2)
                HStack {
                    Text(latestReminder.displayDate.formatted(date: .abbreviated, time: .shortened))
                    Spacer()
                    Button { editingReminder = latestReminder } label: {
                        Image(systemName: "pencil").frame(width: 34, height: 30)
                    }
                    .accessibilityLabel("Editar \(latestReminder.title)")
                    Button(role: .destructive) { deleteReminder(latestReminder) } label: {
                        Image(systemName: "trash").frame(width: 34, height: 30)
                    }
                    .tint(LenaraColors.error)
                    .accessibilityLabel("Eliminar \(latestReminder.title)")
                }
                .font(.caption)
                .foregroundStyle(LenaraColors.textSecondary)
            } else {
                Text("Todavía no tienes recordatorios.")
                    .font(.subheadline)
                    .foregroundStyle(LenaraColors.textSecondary)
                Button { showAddReminder = true } label: {
                    Label("Crear recordatorio", systemImage: "plus")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(LenaraColors.logoMint)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LenaraColors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(LenaraColors.divider.opacity(0.7), lineWidth: 1))
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Permisos pendientes", systemImage: "exclamationmark.shield.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LenaraColors.warning)
            Text(missingPermissions.map(\.explanation).joined(separator: " "))
                .font(.caption)
                .foregroundStyle(LenaraColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                requestingPermissions = true
                _Concurrency.Task { @MainActor in
                    let canRequest = await LenaraPermissionManager.hasUndeterminedPermissions()
                    if canRequest {
                        await LenaraPermissionManager.requestUndeterminedPermissions()
                        let reminders = (try? modelContext.fetch(FetchDescriptor<Reminder>())) ?? []
                        await LocalNotificationManager.shared.refreshScheduledReminderCopy(reminders)
                        try? modelContext.save()
                    } else if let url = URL(string: UIApplication.openSettingsURLString) {
                        await UIApplication.shared.open(url)
                    }
                    refreshPermissionStatus()
                    requestingPermissions = false
                }
            } label: {
                Text(requestingPermissions ? "Solicitando permisos…" : hasUnrequestedPermissions ? "Activar permisos" : "Revisar permisos en Ajustes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LenaraColors.logoMint)
            }
            .disabled(requestingPermissions)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LenaraColors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(LenaraColors.warning.opacity(0.4), lineWidth: 1))
    }

    private func refreshPermissionStatus() {
        _Concurrency.Task {
            missingPermissions = await LenaraPermissionManager.missingPermissions()
            hasUnrequestedPermissions = await LenaraPermissionManager.hasUndeterminedPermissions()
        }
    }

    private var header: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    Image("LenaraLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 104, height: 104)
                        .accessibilityLabel("Símbolo de Lenara")
                    Image(systemName: "sparkle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(LenaraColors.logoMint.opacity(0.85))
                        .offset(x: -45, y: -35)
                    Image(systemName: "sparkle")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(LenaraColors.logoMint.opacity(0.65))
                        .offset(x: -31, y: -17)
                }
                .frame(width: 104, height: 104)

                VStack(alignment: .leading, spacing: 0) {
                    Text(greeting)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(LenaraColors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(userName.isEmpty ? "Lenara" : userName)
                        .font(.system(size: 39, weight: .bold, design: .rounded))
                        .tracking(-1.1)
                        .foregroundStyle(LenaraColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    Capsule()
                        .fill(LenaraColors.logoMint.opacity(0.8))
                        .frame(width: 24, height: 3)
                        .padding(.top, 5)
                }

                Spacer(minLength: 0)

                Button { showChat = true } label: {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(LenaraColors.logoMint)
                        .frame(width: 46, height: 46)
                        .background(LenaraColors.surface.opacity(0.9), in: Circle())
                }
                .accessibilityLabel("Abrir chat")
            }
            Rectangle().fill(LenaraColors.divider.opacity(0.9)).frame(height: 1)
        }
    }

    private var composer: some View {
        HStack(spacing: 12) {
            Button { showVoice = true } label: {
                Image(systemName: "mic")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(LenaraColors.logoMint)
                    .frame(width: 44, height: 46)
            }
            .accessibilityLabel("Dictar mensaje o recuerdo")

            TextField("Escribe lo que necesitas…", text: $chatInput, axis: .vertical)
                .lineLimit(1...4)
                .focused($chatInputFocused)
                .font(.body)
                .tint(LenaraColors.logoMint)
                .submitLabel(.send)
                .onSubmit(openChat)

            Button(action: openChat) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LenaraColors.onAccent)
                    .frame(width: 36, height: 36)
                    .background(LenaraColors.accent, in: Circle())
            }
            .disabled(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            .accessibilityLabel("Enviar al chat")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(LenaraColors.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(LenaraColors.divider.opacity(0.7), lineWidth: 1))
    }

    private func strongAlarmBanner(_ reminder: Reminder) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Alarma fuerte activa", systemImage: "alarm.waves.left.and.right.fill")
                .font(.headline)
                .foregroundStyle(LenaraColors.textPrimary)
            Text(reminder.title)
                .font(.subheadline)
                .foregroundStyle(LenaraColors.textSecondary)
            Button("Ver / Posponer") { openReminder(reminder, isDelivery: true) }
            Button { stopStrongAlarm(reminder) } label: {
                Text("Detener alarma fuerte")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(LenaraColors.error)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LenaraColors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(LenaraColors.error.opacity(0.5), lineWidth: 1))
    }

    private func openReminder(_ reminder: Reminder, isDelivery: Bool = false) {
        ReminderNotificationRouter.shared.route = ReminderNotificationRoute(reminderID: reminder.id, deliveredAt: .now, isDelivery: isDelivery)
    }

    private func stopStrongAlarm(_ reminder: Reminder) {
        LocalNotificationManager.shared.acknowledge(reminder)
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            reminderError = "No se pudo detener la alarma fuerte. Inténtalo otra vez."
        }
    }

    private var tasksButton: some View {
        Button { showTasksManager = true } label: {
            Label("Tareas", systemImage: "checklist")
                .font(.headline.weight(.semibold))
                .foregroundStyle(LenaraColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(LenaraColors.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(LenaraColors.divider.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Otros recordatorios")
            if otherUpcomingReminders.isEmpty {
                Text("No tienes otros recordatorios próximos.")
                    .font(.subheadline)
                    .foregroundStyle(LenaraColors.textSecondary)
            }
            ForEach(otherUpcomingReminders, id: \.id) { reminder in
                HStack(spacing: 12) {
                    Circle().fill(LenaraColors.logoMint).frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reminder.title).onTapGesture { openReminder(reminder) }.font(.body).foregroundStyle(LenaraColors.textPrimary)
                        Text(reminder.displayDate.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(LenaraColors.textSecondary)
                    }
                    Spacer(minLength: 4)
                    Button { editingReminder = reminder } label: { Image(systemName: "pencil").frame(width: 34, height: 38) }.accessibilityLabel("Editar \(reminder.title)")
                    Button(role: .destructive) { deleteReminder(reminder) } label: { Image(systemName: "trash").frame(width: 34, height: 38) }.accessibilityLabel("Eliminar \(reminder.title)")
                }
                .padding(.vertical, 5)
                if reminder.id != otherUpcomingReminders.last?.id { Rectangle().fill(LenaraColors.divider).frame(height: 1) }
            }
            if !pastReminders.isEmpty {
                Button { withAnimation(.easeInOut(duration: 0.2)) { showPastReminders.toggle() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: showPastReminders ? "eye.slash" : "eye")
                            .font(.system(size: 16, weight: .medium))
                        Text(showPastReminders ? "Ocultar recordatorios pasados" : "Ver recordatorios pasados")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: showPastReminders ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(LenaraColors.logoMint)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if showPastReminders && !pastReminders.isEmpty {
                HStack {
                    Text("Recordatorios pasados").font(.rounded(.subheadline)).foregroundStyle(LenaraColors.textSecondary)
                    Spacer()
                    Button(role: .destructive) { showClearPastRemindersConfirmation = true } label: {
                        Label("Eliminar todos", systemImage: "trash")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                }
                ForEach(pastReminders, id: \.id) { reminder in
                    HStack(spacing: 12) {
                        Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "clock").foregroundStyle(LenaraColors.textTertiary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reminder.title).onTapGesture { openReminder(reminder) }.font(.body).foregroundStyle(LenaraColors.textSecondary).lineLimit(2)
                            Text(reminder.displayDate.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(LenaraColors.textTertiary)
                        }
                        Spacer(minLength: 4)
                        Button { editingReminder = reminder } label: { Image(systemName: "pencil").frame(width: 34, height: 38) }.accessibilityLabel("Editar \(reminder.title)")
                        Button(role: .destructive) { deleteReminder(reminder) } label: { Image(systemName: "trash").frame(width: 34, height: 38) }.accessibilityLabel("Eliminar \(reminder.title)")
                    }
                    .padding(.vertical, 5)
                    if reminder.id != pastReminders.last?.id { Rectangle().fill(LenaraColors.divider).frame(height: 1) }
                }
            }
        }
    }

    private var pastReminders: [Reminder] { storedReminders.filter { $0.isCompleted || (!$0.repeats && $0.date <= clockNow && ($0.snoozedUntil ?? .distantPast) <= clockNow) }.sorted { $0.date > $1.date } }

    private func deleteAllPastReminders() {
        for reminder in pastReminders {
            LocalNotificationManager.shared.cancelReminder(reminder)
            modelContext.delete(reminder)
        }
        do { try modelContext.save() }
        catch { modelContext.rollback(); reminderError = "No se pudieron eliminar los recordatorios pasados." }
        showPastReminders = false
    }

    private var widgetTaskSnapshot: [WidgetTaskSnapshot] {
        storedTasks.map { task in
            let payload = TaskChecklistCodec.decode(task.detail)
            return WidgetTaskSnapshot(id: task.id.uuidString, title: task.title, items: payload.items, updatedAt: task.createdAt)
        }
    }

    private func syncWidgetChecklistFromStore() {
        let snapshots = Dictionary(uniqueKeysWithValues: WidgetSharedStore.readTasks().map { ($0.id, $0) })
        var changed = false
        for task in storedTasks {
            guard let snapshot = snapshots[task.id.uuidString] else { continue }
            let payload = TaskChecklistCodec.decode(task.detail)
            guard payload.items != snapshot.items else { continue }
            task.detail = TaskChecklistCodec.encode(description: payload.description, items: snapshot.items)
            if !snapshot.items.isEmpty {
                task.status = snapshot.items.allSatisfy(\.isCompleted) ? .completed : .pending
                task.completedAt = task.status == .completed ? .now : nil
            }
            changed = true
        }
        if changed { try? modelContext.save() }
        if let firstTask = widgetTaskSnapshot.first {
            WidgetSharedStore.selectDefaultTaskIfNeeded(id: firstTask.id)
        }
        WidgetSharedStore.writeTasks(widgetTaskSnapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: "LenaraChecklist")
    }

    private func deleteReminder(_ reminder: Reminder) {
        LocalNotificationManager.shared.cancelReminder(reminder)
        modelContext.delete(reminder)
        do { try modelContext.save() } catch { modelContext.rollback(); reminderError = "No se pudo eliminar el recordatorio." }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Tareas pendientes")
            VStack(alignment: .leading, spacing: 12) {
                ForEach(pendingTasks, id: \.id) { task in
                    let payload = TaskChecklistCodec.decode(task.detail)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(LenaraColors.logoMint)
                            Text(task.title).font(.body.weight(.medium)).foregroundStyle(LenaraColors.textPrimary)
                        }
                        ForEach(payload.items) { item in
                            Button { toggleChecklistItem(item, in: task) } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(item.isCompleted ? LenaraColors.success : LenaraColors.textTertiary)
                                    Text(item.title).font(.subheadline).foregroundStyle(LenaraColors.textSecondary)
                                        .strikethrough(item.isCompleted)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 7)
                    if task.id != pendingTasks.last?.id { Rectangle().fill(LenaraColors.divider).frame(height: 1) }
                }
            }
            .frame(height: showAllPendingTasks ? nil : 270, alignment: .top)
            .clipped()
            .overlay(alignment: .bottom) {
                if !showAllPendingTasks && pendingTasks.count > 1 {
                    LinearGradient(
                        colors: [LenaraColors.background.opacity(0.02), LenaraColors.background.opacity(0.96)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 62)
                    .allowsHitTesting(false)
                }
            }

            if pendingTasks.count > 1 {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showAllPendingTasks.toggle() }
                } label: {
                    Label(showAllPendingTasks ? "Mostrar menos" : "Ver anteriores",
                          systemImage: showAllPendingTasks ? "chevron.up" : "arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LenaraColors.logoMint)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(LenaraColors.surface.opacity(0.96), in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            }
        }
    }

    private func toggleChecklistItem(_ item: WidgetChecklistItem, in task: Task) {
        var payload = TaskChecklistCodec.decode(task.detail)
        guard let index = payload.items.firstIndex(where: { $0.id == item.id }) else { return }
        payload.items[index].isCompleted.toggle()
        task.detail = TaskChecklistCodec.encode(description: payload.description, items: payload.items)
        task.status = payload.items.allSatisfy(\.isCompleted) ? .completed : .pending
        task.completedAt = task.status == .completed ? .now : nil
        try? modelContext.save()
    }

    private func sectionHeading(_ text: String) -> some View {
        HStack {
            Text(text).font(.rounded(.headline)).foregroundStyle(LenaraColors.textPrimary)
            Spacer()
        }
    }

    private func openChat() {
        guard !chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        chatInputFocused = false
        showChat = true
    }
}

#Preview { HomeTab() }

struct LenaraBackground: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                LenaraColors.background

                RadialGradient(
                    colors: [Color(red: 0.02, green: 0.42, blue: 0.27).opacity(0.52), .clear],
                    center: .center,
                    startRadius: 12,
                    endRadius: width * 0.8
                )
                .frame(width: width * 1.65, height: width * 1.65)
                .offset(x: width * 0.45, y: -height * 0.39)
                .blur(radius: 20)

                Path { path in
                    path.move(to: CGPoint(x: width * 0.53, y: -height * 0.06))
                    path.addCurve(
                        to: CGPoint(x: width * 1.12, y: height * 0.20),
                        control1: CGPoint(x: width * 0.68, y: height * 0.08),
                        control2: CGPoint(x: width * 0.84, y: height * 0.14)
                    )
                }
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.35, blue: 0.24).opacity(0.12),
                            Color(red: 0.06, green: 0.31, blue: 0.22).opacity(0.46),
                            Color(red: 0.03, green: 0.24, blue: 0.18).opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: width * 0.48, lineCap: .round)
                )
                .blur(radius: 24)

                LinearGradient(
                    colors: [.clear, LenaraColors.background.opacity(0.36)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: width, height: height)
            .clipped()
        }
        .allowsHitTesting(false)
    }
}

private struct WidgetTaskSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Task.createdAt, order: .reverse) private var tasks: [Task]
    @State private var showNewTask = false
    @State private var selectedTaskID = WidgetSharedStore.selectedTaskID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Seleccionar tarea a mostrar en el widget")
                        .font(.rounded(.title2))
                        .foregroundStyle(LenaraColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)

                    if tasks.isEmpty {
                        ContentUnavailableView("Aún no hay tareas", systemImage: "checklist", description: Text("Crea una tarea para elegirla en el widget."))
                    } else {
                        ForEach(tasks, id: \.id) { task in
                        NavigationLink {
                            WidgetTaskDetailSheet(task: task, isSelected: selectedTaskID == task.id.uuidString) {
                                    if selectedTaskID == task.id.uuidString {
                                        selectedTaskID = nil
                                        WidgetSharedStore.clearSelectedTask()
                                    } else {
                                        selectedTaskID = task.id.uuidString
                                        WidgetSharedStore.selectTask(id: task.id.uuidString)
                                    }
                                WidgetCenter.shared.reloadTimelines(ofKind: "LenaraChecklist")
                            }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(task.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(LenaraColors.textPrimary)
                                        .lineLimit(2)
                                    if selectedTaskID == task.id.uuidString {
                                        Text("Se muestra en el widget")
                                            .font(.caption)
                                            .foregroundStyle(LenaraColors.logoMint)
                                    } else if task.status == .completed {
                                        Text("Completada")
                                            .font(.caption)
                                            .foregroundStyle(LenaraColors.textTertiary)
                                    }
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(LenaraColors.textTertiary)
                            }
                            .padding(16)
                            .background(LenaraColors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .background(LenaraColors.background)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Nueva tarea") { showNewTask = true }
                }
            }
            .sheet(isPresented: $showNewTask) {
                AddTaskSheet().preferredColorScheme(.dark)
            }
        }
    }
}

private struct WidgetTaskDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let task: Task
    let isSelected: Bool
    let selectForWidget: () -> Void

    private var payload: TaskChecklistCodec.Payload { TaskChecklistCodec.decode(task.detail) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(task.title)
                        .font(.rounded(.title2))
                        .foregroundStyle(LenaraColors.textPrimary)
                    if !payload.description.isEmpty {
                        Text(payload.description)
                            .font(.body)
                            .foregroundStyle(LenaraColors.textSecondary)
                    }
                    if !payload.items.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Pendientes")
                                .font(.headline)
                                .foregroundStyle(LenaraColors.textPrimary)
                            ForEach(payload.items) { item in
                                Button { togglePending(item.id) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(item.isCompleted ? LenaraColors.success : LenaraColors.textTertiary)
                                        Text(item.title)
                                            .foregroundStyle(item.isCompleted ? LenaraColors.textTertiary : LenaraColors.textSecondary)
                                            .strikethrough(item.isCompleted)
                                        Spacer(minLength: 0)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(item.isCompleted ? "Marcar pendiente: \(item.title)" : "Completar: \(item.title)")
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LenaraColors.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    Button {
                        selectForWidget()
                        dismiss()
                    } label: {
                        Text(isSelected ? "Quitar de inicio" : "Mostrar en inicio")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(LenaraColors.accent)
                }
                .padding(20)
            }
            .background(LenaraColors.background)
            .navigationTitle("Tarea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }

    private func togglePending(_ itemID: String) {
        var updatedPayload = TaskChecklistCodec.decode(task.detail)
        guard let index = updatedPayload.items.firstIndex(where: { $0.id == itemID }) else { return }
        updatedPayload.items[index].isCompleted.toggle()
        task.detail = TaskChecklistCodec.encode(description: updatedPayload.description, items: updatedPayload.items)
        task.status = updatedPayload.items.allSatisfy(\.isCompleted) ? .completed : .pending
        task.completedAt = task.status == .completed ? .now : nil
        do {
            try modelContext.save()
            WidgetCenter.shared.reloadTimelines(ofKind: "LenaraChecklist")
        } catch {
            modelContext.rollback()
        }
    }
}
