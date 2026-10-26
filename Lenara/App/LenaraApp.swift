import SwiftUI
import SwiftData

@main
struct LenaraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            OnboardingView()
                .modelContainer(LenaraStore.container)
                .preferredColorScheme(nil)
        }
    }
}
