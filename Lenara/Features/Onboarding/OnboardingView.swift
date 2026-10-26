import SwiftUI
import AVFoundation
import Speech
import UserNotifications

struct OnboardingView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var notificationRouter = ReminderNotificationRouter.shared
    @State private var step = 0
    @State private var draftName = ""
    @State private var isRequestingPermissions = false
    @StateObject private var dictation = ReminderDictationRoute.shared
    @State private var createTaskFromWidget = false
    @AppStorage("lenara.userName") private var userName = ""
    @AppStorage("lenara.onboardingComplete") private var onboardingComplete = false

    var body: some View {
        Group {
            if !onboardingComplete {
                if step == 0 {
                    WelcomeScreen { withAnimation(.easeInOut(duration: 0.25)) { step = 1 } }
                } else {
                    NameEntryScreen(name: $draftName, isLoading: isRequestingPermissions) {
                        continueAfterName()
                    }
                }
            } else if dictation.isPresented {
                WidgetVoiceCaptureScreen { dictation.isPresented = false }
            } else {
                ContentView(createTaskFromWidget: $createTaskFromWidget)
            }
        }
        .fullScreenCover(item: $notificationRouter.route) { route in
            ReminderDetailSheet(route: route)
        }
        .animation(.easeInOut(duration: 0.22), value: step)
        .onOpenURL { url in
            guard url.scheme == "lenara", onboardingComplete else { return }
            if url.host == "capture-reminder" {
                notificationRouter.route = nil
                dictation.isPresented = true
            } else if url.host == "select-widget-task" || url.host == "create-task" {
                dictation.isPresented = false
                createTaskFromWidget = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                dictation.isPresented = false
                if !onboardingComplete && userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draftName = ""
                    step = 0
                }
            }
        }
    }

    private func continueAfterName() {
        let cleanName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !isRequestingPermissions else { return }
        userName = cleanName
        isRequestingPermissions = true

        _Concurrency.Task {
            await LenaraPermissionManager.requestUndeterminedPermissions()
            isRequestingPermissions = false
            onboardingComplete = true
        }
    }
}

private struct WelcomeScreen: View {
    let onAccept: () -> Void

    var body: some View {
        ZStack {
            LenaraBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    welcomeHero
                        .padding(.top, 8)

                    Text("Tu espacio personal,\nsiempre contigo.")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(LenaraColors.accent)
                        .multilineTextAlignment(.center)

                    Text("Una app de recordatorios, tareas y memorias que funciona 100% en tu dispositivo, sin conexión a internet.")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(LenaraColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)

                    OnboardingFeatureCard(icon: "mic.fill", title: "Dicta por voz", detail: "Agrega tareas, recuerdos o ideas hablando, o escribe si prefieres.")
                    OnboardingFeatureCard(icon: "list.bullet", title: "Organiza tus tareas", detail: "Crea listas, marca lo completado y mantén todo en orden.")
                    OnboardingFeatureCard(icon: "bookmark", title: "Guarda tus memorias", detail: "Registra recuerdos, ideas o notas importantes para cuando las necesites.")
                    OnboardingFeatureCard(icon: "lock", title: "Todo en tu dispositivo", detail: "Tu información se mantiene solo en tu equipo. Sin internet, sin envíos, sin preocupaciones.")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                OnboardingPrimaryButton(title: "Aceptar", action: onAccept)
                    .padding(.horizontal, 27)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                    .background(LinearGradient(colors: [LenaraColors.background.opacity(0.02), LenaraColors.background.opacity(0.96)], startPoint: .top, endPoint: .bottom))
            }
        }
        .preferredColorScheme(.dark)
    }

    private var welcomeHero: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .stroke(LenaraColors.logoMint.opacity(0.4), lineWidth: 1)
                    .frame(width: 225, height: 225)
                Image("LenaraLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 222, height: 222)
                    .accessibilityHidden(true)
                OnboardingOrbitIcon(systemName: "mic", tint: LenaraColors.logoMint)
                    .offset(x: -126, y: -8)
                OnboardingOrbitIcon(systemName: "list.bullet", tint: LenaraColors.logoMint)
                    .offset(x: 126, y: 22)
                Image(systemName: "sparkle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(LenaraColors.logoMint)
                    .offset(x: -100, y: -101)
                Image(systemName: "sparkle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LenaraColors.logoMint.opacity(0.9))
                    .offset(x: 105, y: -50)
            }
            .frame(height: 246)

            Text("Lenara")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .tracking(-1.2)
                .foregroundStyle(LenaraColors.textPrimary)
                .padding(.top, -3)
        }
    }
}

private struct NameEntryScreen: View {
    @Binding var name: String
    let isLoading: Bool
    let onContinue: () -> Void
    @FocusState private var nameFieldFocused: Bool

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack {
            LenaraBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 60)

                VStack(spacing: 8) {
                    Text("Para empezar,")
                        .font(.system(size: 29, weight: .regular, design: .rounded))
                        .foregroundStyle(LenaraColors.textPrimary)
                    Text("dime tu nombre.")
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .foregroundStyle(LenaraColors.accent)
                    Text("Así podré dirigirme a ti.")
                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .foregroundStyle(LenaraColors.textSecondary)
                        .padding(.top, 12)
                }

                HStack(spacing: 16) {
                    Image(systemName: "person")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(LenaraColors.logoMint)
                    TextField("Tu nombre", text: $name)
                        .font(.system(size: 18, weight: .regular, design: .rounded))
                        .foregroundStyle(LenaraColors.textPrimary)
                        .tint(LenaraColors.logoMint)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .submitLabel(.continue)
                        .focused($nameFieldFocused)
                        .onSubmit { if !cleanName.isEmpty { onContinue() } }
                }
                .padding(.horizontal, 20)
                .frame(height: 58)
                .background(LenaraColors.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(LenaraColors.logoMint.opacity(0.48), lineWidth: 1))
                .padding(.horizontal, 36)
                .padding(.top, 46)

                Spacer(minLength: 40)

                OnboardingPrimaryButton(title: "Continuar", action: onContinue, isLoading: isLoading)
                    .disabled(cleanName.isEmpty || isLoading)
                    .opacity(cleanName.isEmpty || isLoading ? 0.55 : 1)
                    .padding(.horizontal, 27)
                    .padding(.bottom, 18)
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct OnboardingFeatureCard: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 17) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(LenaraColors.logoMint)
                .frame(width: 54, height: 54)
                .background(LenaraColors.logoMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(LenaraColors.textPrimary)
                Text(detail)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LenaraColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LenaraColors.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(LenaraColors.divider.opacity(0.42), lineWidth: 1))
    }
}

private struct OnboardingOrbitIcon: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 21, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 58, height: 58)
            .background(LenaraColors.surface.opacity(0.96), in: Circle())
            .overlay(Circle().stroke(tint.opacity(0.38), lineWidth: 1))
            .shadow(color: .black.opacity(0.24), radius: 12, y: 5)
    }
}

private struct OnboardingPrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading { ProgressView().tint(LenaraColors.onAccent) }
                Text(isLoading ? "Preparando Lenara…" : title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(LenaraColors.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(LenaraColors.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

enum LenaraPermission: String, Identifiable {
    case notifications
    case microphone
    case speechRecognition

    var id: String { rawValue }
    var title: String {
        switch self {
        case .notifications: "Notificaciones"
        case .microphone: "Micrófono"
        case .speechRecognition: "Reconocimiento de voz"
        }
    }

    var explanation: String {
        switch self {
        case .notifications: "Sin este permiso, Lenara no podrá avisarte a la hora de tus recordatorios."
        case .microphone: "Sin este permiso, Lenara no podrá escuchar tus pedidos hablados."
        case .speechRecognition: "Sin este permiso, Lenara no podrá convertir tu voz en texto para guardar pedidos y notas."
        }
    }
}

enum LenaraPermissionManager {
    static func hasUndeterminedPermissions() async -> Bool {
        let notifications = await UNUserNotificationCenter.current().notificationSettings()
        return notifications.authorizationStatus == .notDetermined
            || SFSpeechRecognizer.authorizationStatus() == .notDetermined
            || AVAudioApplication.shared.recordPermission == .undetermined
    }

    static func requestUndeterminedPermissions() async {
        let center = UNUserNotificationCenter.current()
        let notificationSettings = await center.notificationSettings()
        if notificationSettings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }

        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                SFSpeechRecognizer.requestAuthorization { _ in continuation.resume(returning: ()) }
            }
        }

        if AVAudioApplication.shared.recordPermission == .undetermined {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                AVAudioApplication.requestRecordPermission { _ in continuation.resume(returning: ()) }
            }
        }
    }

    static func missingPermissions() async -> [LenaraPermission] {
        var missing: [LenaraPermission] = []

        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        let notificationAllowed = notificationSettings.authorizationStatus == .authorized
            || notificationSettings.authorizationStatus == .provisional
        if !notificationAllowed || notificationSettings.alertSetting != .enabled || notificationSettings.soundSetting != .enabled {
            missing.append(.notifications)
        }
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            missing.append(.speechRecognition)
        }
        if AVAudioApplication.shared.recordPermission != .granted {
            missing.append(.microphone)
        }
        return missing
    }
}
