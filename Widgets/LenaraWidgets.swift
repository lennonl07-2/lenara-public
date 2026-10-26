import AppIntents
import SwiftUI
import WidgetKit

private let forest = Color(red: 0.075, green: 0.137, blue: 0.102)
private let leaf = Color(red: 0.69, green: 0.80, blue: 0.69)
private let mint = Color(red: 0.42, green: 0.78, blue: 0.76)

@main
struct LenaraWidgetBundle: WidgetBundle {
    var body: some Widget {
        VoiceCaptureWidget()
        ChecklistWidget()
        if #available(iOS 18.0, *) {
            ReminderCaptureControl()
            ReminderCaptureLiveActivity()
        }
    }
}

struct VoiceCaptureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LenaraVoiceCapture", provider: EmptyWidgetProvider()) { _ in
            Link(destination: URL(string: "lenara://capture-reminder")!) {
                VStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 31, weight: .medium))
                        .foregroundStyle(forest)
                        .frame(width: 60, height: 60)
                        .background(mint, in: Circle())
                    Text("Hablar con Lenara").font(.caption.weight(.semibold)).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .containerBackground(forest.gradient, for: .widget)
        }
        .configurationDisplayName("Micrófono de Lenara")
        .description("Toca para dictar un recordatorio.")
        .supportedFamilies([.systemSmall])
    }
}

struct ChecklistWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LenaraChecklist", provider: ChecklistProvider()) { entry in
            ChecklistWidgetView(tasks: entry.tasks, selectedTaskID: entry.selectedTaskID)
        }
        .configurationDisplayName("Tareas de Lenara")
        .description("Elige qué tarea mostrar y marca sus pendientes desde la pantalla de inicio.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct EmptyWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ChecklistEntry { ChecklistEntry(date: .now, tasks: [], selectedTaskID: nil) }
    func getSnapshot(in context: Context, completion: @escaping (ChecklistEntry) -> Void) { completion(ChecklistEntry(date: .now, tasks: [], selectedTaskID: nil)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ChecklistEntry>) -> Void) {
        completion(Timeline(entries: [ChecklistEntry(date: .now, tasks: [], selectedTaskID: nil)], policy: .never))
    }
}

private struct ChecklistProvider: TimelineProvider {
    func placeholder(in context: Context) -> ChecklistEntry { ChecklistEntry(date: .now, tasks: [], selectedTaskID: nil) }
    func getSnapshot(in context: Context, completion: @escaping (ChecklistEntry) -> Void) {
        completion(ChecklistEntry(date: .now, tasks: WidgetSharedStore.readTasks(), selectedTaskID: WidgetSharedStore.selectedTaskID()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ChecklistEntry>) -> Void) {
        let entry = ChecklistEntry(date: .now, tasks: WidgetSharedStore.readTasks(), selectedTaskID: WidgetSharedStore.selectedTaskID())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

private struct ChecklistEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTaskSnapshot]
    let selectedTaskID: String?
}

private struct ChecklistWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let tasks: [WidgetTaskSnapshot]
    let selectedTaskID: String?

    private var displayedTask: WidgetTaskSnapshot? {
        guard let selectedTaskID else { return nil }
        return tasks.first(where: { $0.id == selectedTaskID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(displayedTask?.title ?? "Mis tareas")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .center)
            if let first = displayedTask {
                if first.items.isEmpty {
                    Text("Abre Lenara para añadir pasos").font(.caption2).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
                } else {
                    ForEach(Array(first.items.prefix(family == .systemSmall ? 3 : 4))) { item in
                        Button(intent: ToggleChecklistIntent(itemID: item.id)) {
                            HStack(spacing: 6) {
                                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isCompleted ? mint : leaf.opacity(0.8))
                                Text(item.title)
                                    .foregroundStyle(item.isCompleted ? .white.opacity(0.52) : .white.opacity(0.92))
                                    .strikethrough(item.isCompleted)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .font(.caption2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("Toca para elegir una tarea")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .containerBackground(forest.gradient, for: .widget)
        .widgetURL(URL(string: "lenara://select-widget-task"))
    }
}

struct ToggleChecklistIntent: AppIntent {
    static var title: LocalizedStringResource = "Marcar paso de tarea"
    static var description = IntentDescription("Marca o desmarca un paso de una tarea de Lenara.")
    @Parameter(title: "Paso") var itemID: String

    init() { itemID = "" }
    init(itemID: String) { self.itemID = itemID }

    func perform() async throws -> some IntentResult {
        WidgetSharedStore.toggle(itemID: itemID)
        WidgetCenter.shared.reloadTimelines(ofKind: "LenaraChecklist")
        return .result()
    }
}
