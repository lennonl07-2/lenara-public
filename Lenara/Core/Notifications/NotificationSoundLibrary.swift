import Foundation

struct LenaraNotificationSound: Identifiable {
    let title: String
    let fileName: String
    var id: String { fileName }
}

enum NotificationSoundLibrary {
    static let sounds = [
        LenaraNotificationSound(title: "Aurora", fileName: "NotificationAurora.wav"),
        LenaraNotificationSound(title: "Chispa", fileName: "NotificationChispa.wav"),
        LenaraNotificationSound(title: "Campanita", fileName: "NotificationCampanita.wav")
    ]
}
