import SwiftUI

@MainActor
final class ReminderDictationRoute: ObservableObject {
    static let shared = ReminderDictationRoute()
    @Published var isPresented = false
}
