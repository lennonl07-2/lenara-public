import XCTest
import SwiftData
import UIKit
@testable import Lenara

final class VoiceReminderTests: XCTestCase {
    @MainActor func testRecordingKeepsAppAwakeAndRestoresTimerOnCancel() async throws {
        let previous = UIApplication.shared.isIdleTimerDisabled
        let capture = VoiceCaptureModel()
        defer {
            capture.cancel()
            UIApplication.shared.isIdleTimerDisabled = previous
        }
        UIApplication.shared.isIdleTimerDisabled = false
        await capture.start()
        guard capture.isRecording else { throw XCTSkip(capture.errorMessage ?? "Microphone unavailable") }
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        capture.cancel()
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }

    func testSpokenSendRemovesOnlyExplicitTrailingCommand() {
        XCTAssertEqual(VoiceReminderService.requestBeforeSendCommand("Tomar agua en diez minutos. Lenara, enviar."), "Tomar agua en diez minutos")
        XCTAssertNil(VoiceReminderService.requestBeforeSendCommand("Recuérdame enviar un correo en diez minutos"))
        XCTAssertNil(VoiceReminderService.requestBeforeSendCommand("Lenara, enviar"))
        XCTAssertNil(VoiceReminderService.requestBeforeSendCommand("Tomar agua en diez minutos, Lenara enviar y algo más"))
    }

    func testBareDictationIsReminder() throws {
        let now = Date.now
        let intent = try VoiceReminderService.parse("tomar agua dentro de diez minutos", now: now)
        XCTAssertEqual(intent.action, .createReminder)
        XCTAssertEqual(intent.title, "tomar agua")
        XCTAssertEqual(intent.date!.timeIntervalSince(now), 600, accuracy: 1)
    }

    func testRejectsNotesTasksAndEmptySpeech() {
        for phrase in ["", "   ", "guarda mi idea de negocio", "nueva tarea: limpiar", "hola"] {
            XCTAssertThrowsError(try VoiceReminderService.parse(phrase), phrase)
        }
    }

    func testRejectsMissingAndAmbiguousTime() {
        for phrase in ["comprar pan", "recuérdame comprar pan mañana a las cinco", "tomar agua todos los días a las nueve"] {
            XCTAssertThrowsError(try VoiceReminderService.parse(phrase), phrase)
        }
    }

    @MainActor private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Memory.self, Task.self, Reminder.self, ConversationMessage.self, configurations: configuration)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    @MainActor func testSaveOnlyCreatesReminderAndPreservesRepeatingSlots() async throws {
        let context = try makeContext()
        var scheduled = 0
        try await VoiceReminderService.save("tomar agua todos los días a las 9 am y a las 6 pm", in: context, schedule: { reminder in
            scheduled += 1
            XCTAssertEqual(Set(reminder.scheduleSlots.map(\.hour)), [9, 18])
        }, cancel: { _ in XCTFail("Should not cancel a successful save") })
        XCTAssertEqual(scheduled, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Reminder>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Memory>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Task>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ConversationMessage>()), 0)
    }

    @MainActor func testSchedulingFailureLeavesNothingSaved() async throws {
        let context = try makeContext()
        var cancelled = false
        do {
            try await VoiceReminderService.save("tomar agua dentro de diez minutos", in: context,
                schedule: { _ in throw VoiceReminderError.invalid("Sin permiso") }, cancel: { _ in cancelled = true })
            XCTFail("Expected scheduling failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Sin permiso")
        }
        XCTAssertTrue(cancelled)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Reminder>()), 0)
    }

    @MainActor func testRepeatedSendDoesNotDuplicate() async throws {
        let context = try makeContext()
        var scheduled = 0
        for _ in 0..<2 {
            try await VoiceReminderService.save("tomar agua dentro de diez minutos", in: context,
                schedule: { _ in scheduled += 1 }, cancel: { _ in })
        }
        XCTAssertEqual(scheduled, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Reminder>()), 1)
    }
}
