import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct ReminderCaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ReminderCaptureControlState.kind) {
            ControlWidgetButton(action: StartReminderCaptureIntent()) {
                Label("Dictar recordatorio", image: "LenaraLockSymbol")
            }
        }
        .displayName("Dictar recordatorio")
        .description("Abre solo el dictado, mantiene la pantalla encendida y guarda sin abrir el chat.")
    }
}

@available(iOS 18.0, *)
struct ReminderCaptureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReminderCaptureAttributes.self) { context in
            HStack(spacing: 14) {
                Image("LenaraLockLogo")
                    .resizable().scaledToFit().frame(width: 48, height: 48)
                    .foregroundStyle(.white).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Lenara").font(.caption).foregroundStyle(.secondary)
                    Text(context.state.message).font(.subheadline.weight(.semibold)).lineLimit(3)
                    if context.state.phase == .listening || context.state.phase == .ready {
                        captureButtons(context)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: statusSymbol(context.state.phase)).foregroundStyle(.mint)
            }
            .padding(18)
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
            .foregroundStyle(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { logo }
                DynamicIslandExpandedRegion(.center) { Text(context.state.message).font(.caption).lineLimit(2) }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.phase == .listening || context.state.phase == .ready { captureButtons(context) }
                }
            } compactLeading: {
                logo
            } compactTrailing: {
                Image(systemName: statusSymbol(context.state.phase))
            } minimal: {
                logo
            }
        }
    }

    private var logo: some View {
        Image("LenaraLockLogo").resizable().scaledToFit()
            .frame(width: 22, height: 22).foregroundStyle(.white).accessibilityHidden(true)
    }

    private func captureButtons(_ context: ActivityViewContext<ReminderCaptureAttributes>) -> some View {
        HStack(spacing: 12) {
            Button(intent: SendReminderCaptureIntent(sessionID: context.attributes.sessionID)) {
                Label("Enviar", systemImage: "arrow.up.circle.fill")
            }
            .tint(.mint)
            Button(intent: CancelReminderCaptureIntent(sessionID: context.attributes.sessionID)) {
                Image(systemName: "xmark").accessibilityLabel("Cancelar dictado")
            }
            .tint(.gray)
        }
        .buttonStyle(.bordered)
    }

    private func statusSymbol(_ phase: ReminderCaptureAttributes.Phase) -> String {
        switch phase {
        case .listening: return "waveform"
        case .ready: return "mic.slash"
        case .saving: return "ellipsis"
        case .saved: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle"
        }
    }
}
