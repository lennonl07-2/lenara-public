import SwiftUI
import SwiftData
import UserNotifications

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedIndex = 0
    @Binding var createTaskFromWidget: Bool

    init(createTaskFromWidget: Binding<Bool> = .constant(false)) {
        _createTaskFromWidget = createTaskFromWidget
    }

    let tabs = [
        TabItem(icon: "house.fill", title: "Inicio", selectedTitle: "Inicio"),
        TabItem(icon: "book.closed", title: "Memoria", selectedTitle: "Memoria"),
        TabItem(icon: "gearshape.fill", title: "Ajustes", selectedTitle: "Ajustes")
    ]

    var body: some View {
        TabView(selection: $selectedIndex) {
            HomeTab(createTaskFromWidget: $createTaskFromWidget)
                .tabItem {
                    Label(tabs[0].title, systemImage: tabs[0].icon)
                }
                .tag(0)

            MemoryTab()
                .tabItem {
                    Label(tabs[1].title, systemImage: tabs[1].icon)
                }
                .tag(1)

            SettingsTab()
                .tabItem {
                    Label(tabs[2].title, systemImage: tabs[2].icon)
                }
                .tag(2)
        }
        .tint(LenaraColors.accent)
        .toolbarBackground(LenaraColors.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .preferredColorScheme(.dark)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refreshReminderCopy()
        }
    }

    @MainActor
    private func refreshReminderCopy() async {
        // Restored onboarding preferences do not imply restored iOS authorization.
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = await LocalNotificationManager.shared.requestAuthorization()
        }
        guard let reminders = try? modelContext.fetch(FetchDescriptor<Reminder>()) else { return }
        await LocalNotificationManager.shared.refreshScheduledReminderCopy(reminders)
        try? modelContext.save()
    }

}

struct TabItem {
    let icon: String
    let title: String
    let selectedTitle: String
}

#Preview {
    ContentView()
}
