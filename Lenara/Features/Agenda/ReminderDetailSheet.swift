import SwiftUI
import SwiftData

struct ReminderDetailSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Query private var reminders: [Reminder]
    let route: ReminderNotificationRoute
    @State private var minutes = 10
    @State private var busy = false
    @State private var error: String?
    private var reminder: Reminder? { reminders.first { $0.id == route.reminderID } }

    var body: some View {
        NavigationStack {
            ZStack {
                LenaraBackground().ignoresSafeArea()
                if let reminder {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            Image(systemName: reminder.isStrongAlarm ? "alarm.fill" : "bell.badge.fill")
                                .font(.system(size: 36)).foregroundStyle(LenaraColors.logoMint)
                                .frame(width: 76, height: 76)
                                .background(LenaraColors.logoMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
                            Text(reminder.title).font(.title2.bold()).foregroundStyle(LenaraColors.textPrimary)
                            VStack(alignment: .leading, spacing: 16) {
                                dateRow("Creado", date: reminder.createdAt)
                                dateRow("Programado para", date: scheduledDate(reminder))
                                if reminder.repeats {
                                    Label(reminder.scheduleDescription, systemImage: "repeat")
                                        .font(.subheadline).foregroundStyle(LenaraColors.logoMint)
                                }
                                if let next = reminder.nextScheduledDate() { dateRow("Próximo aviso", date: next) }
                            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                .background(LenaraColors.surface, in: RoundedRectangle(cornerRadius: 20))
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Volver a avisarme").font(.headline)
                                Picker("Dentro de", selection: $minutes) {
                                    ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
                                }.pickerStyle(.segmented)
                                HStack {
                                    Text("Minutos personalizados")
                                    TextField("Minutos", value: $minutes, format: .number)
                                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                        .frame(width: 80).padding(10)
                                        .background(LenaraColors.surface, in: RoundedRectangle(cornerRadius: 10))
                                }
                                Button { snooze(reminder) } label: {
                                    Label("Posponer \(minutes) minutos", systemImage: "clock.arrow.circlepath")
                                        .frame(maxWidth: .infinity).padding(16)
                                }.buttonStyle(.borderedProminent).tint(LenaraColors.accent)
                                    .disabled(busy || !(1...1440).contains(minutes))
                                Button { acknowledge(reminder) } label: {
                                    Label(reminder.isStrongAlarm ? "Detener alarma" : "OK, cerrar", systemImage: "checkmark.circle")
                                        .frame(maxWidth: .infinity).padding(16)
                                }.buttonStyle(.bordered).disabled(busy)
                                if reminder.repeats {
                                    Text("Posponer o cerrar este aviso mantiene los próximos horarios.")
                                        .font(.footnote).foregroundStyle(LenaraColors.textSecondary)
                                }
                                if reminder.isStrongAlarm {
                                    Text("El sonido continúa con Lenara abierta. Con la app cerrada, iOS reproduce un aviso; respeta los ajustes de sonido del dispositivo.")
                                        .font(.footnote).foregroundStyle(LenaraColors.textSecondary)
                                }
                            }
                        }.padding(24)
                    }
                } else {
                    ContentUnavailableView("Recordatorio eliminado", systemImage: "bell.slash", description: Text("Este aviso pertenece a un recordatorio que ya no está guardado."))
                }
            }
            .navigationTitle("Recordatorio").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if reminder == nil { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } } }
            }
            .alert("Recordatorio", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Aceptar", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .task { playIfNeeded() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { playIfNeeded() } }
    }

    private func scheduledDate(_ reminder: Reminder) -> Date {
        if !route.isDelivery { return reminder.snoozedUntil ?? reminder.nextScheduledDate() ?? reminder.date }
        if let snooze = reminder.snoozedUntil, abs(snooze.timeIntervalSince(route.deliveredAt)) < 120 { return snooze }
        if reminder.repeats {
            return reminder.scheduleSlots.compactMap { slot in
                Calendar.current.nextDate(after: route.deliveredAt.addingTimeInterval(1), matching: slot.components,
                    matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .backward)
            }.max() ?? reminder.date
        }
        return reminder.date
    }

    private func dateRow(_ title: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(LenaraColors.textSecondary)
            Text(date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
        }
    }

    private func playIfNeeded() {
        guard route.isDelivery, let reminder, reminder.isStrongAlarm, !reminder.isCompleted,
              reminder.acknowledgedAt.map({ $0 < route.deliveredAt }) ?? true else { return }
        do { try StrongAlarmPlayer.shared.start(for: reminder.id) }
        catch { self.error = "No se pudo reproducir el sonido de alarma: \(error.localizedDescription)" }
    }

    private func snooze(_ reminder: Reminder) {
        busy = true
        _Concurrency.Task { @MainActor in
            do {
                try await LocalNotificationManager.shared.snooze(reminder, minutes: minutes)
                try context.save()
                dismiss()
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }

    private func acknowledge(_ reminder: Reminder) {
        guard route.isDelivery || (!reminder.repeats && reminder.displayDate <= .now) else { dismiss(); return }
        LocalNotificationManager.shared.acknowledge(reminder)
        do { try context.save(); dismiss() }
        catch { self.error = "El sonido se detuvo, pero no se pudo guardar el estado: \(error.localizedDescription)" }
    }
}
