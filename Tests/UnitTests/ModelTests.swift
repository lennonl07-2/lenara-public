import XCTest
import SwiftData
@testable import Lenara

// MARK: - Memory Tests
class MemoryTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: Memory.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        try await super.tearDown()
        container = nil
        context = nil
    }

    func testCreateMemory() {
        let memory = Memory(title: "Test Memory", content: "This is a test")
        context.insert(memory)

        let fetchDescriptor = FetchDescriptor<Memory>()
        let memories = try! context.fetch(fetchDescriptor)

        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories.first?.title, "Test Memory")
    }

    func testUpdateMemory() {
        let memory = Memory(title: "Original Title", content: "Original Content")
        context.insert(memory)

        memory.title = "Updated Title"
        memory.content = "Updated Content"

        let fetchDescriptor = FetchDescriptor<Memory>()
        let memories = try! context.fetch(fetchDescriptor)

        XCTAssertEqual(memories.first?.title, "Updated Title")
        XCTAssertEqual(memories.first?.content, "Updated Content")
    }

    func testDeleteMemory() {
        let memory = Memory(title: "To Delete", content: "Will be deleted")
        context.insert(memory)

        context.delete(memory)

        let fetchDescriptor = FetchDescriptor<Memory>()
        let memories = try! context.fetch(fetchDescriptor)

        XCTAssertEqual(memories.count, 0)
    }

    func testSearchMemories() {
        let memory1 = Memory(title: "Project Alpha", content: "First project")
        let memory2 = Memory(title: "Project Beta", content: "Second project")
        context.insert(memory1)
        context.insert(memory2)

        let predicate = #Predicate<Memory> { $0.title.contains("Alpha") }
        let descriptor = FetchDescriptor<Memory>(predicate: predicate)
        let results = try! context.fetch(descriptor)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Project Alpha")
    }
}

// MARK: - Task Tests
class TaskTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: Task.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        try await super.tearDown()
        container = nil
        context = nil
    }

    func testCreateTask() {
        let task = Task(title: "Test Task")
        context.insert(task)

        let fetchDescriptor = FetchDescriptor<Task>()
        let tasks = try! context.fetch(fetchDescriptor)

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.title, "Test Task")
        XCTAssertEqual(tasks.first?.status, .pending)
    }

    func testToggleTaskStatus() {
        let task = Task(title: "Toggle Test")
        context.insert(task)

        task.toggleStatus()

        XCTAssertEqual(task.status, .completed)
        XCTAssertNotNil(task.completedAt)

        task.toggleStatus()
        XCTAssertEqual(task.status, .pending)
        XCTAssertNil(task.completedAt)
    }
}

// MARK: - Reminder Tests
class ReminderTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: Reminder.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        try await super.tearDown()
        container = nil
        context = nil
    }

    func testCreateReminder() {
        let reminder = Reminder(title: "Test Reminder", date: Date().addingTimeInterval(3600))
        context.insert(reminder)

        let fetchDescriptor = FetchDescriptor<Reminder>()
        let reminders = try! context.fetch(fetchDescriptor)

        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.title, "Test Reminder")
    }

    func testCompleteReminder() {
        let reminder = Reminder(title: "Complete Test", date: Date())
        context.insert(reminder)

        reminder.isCompleted.toggle()

        XCTAssertTrue(reminder.isCompleted)
    }
}

// MARK: - Intent Parser Tests
class IntentParserTests: XCTestCase {
    let parser = IntentParser()

    func testParseReminderIntent() {
        let intent = parser.parse("Recuérdame comprar pañales mañana a las 7")

        XCTAssertEqual(intent.action, .createReminder)
        XCTAssertNotNil(intent.title)
    }

    func testParseMemoryIntent() {
        let intent = parser.parse("Guarda esta idea: crear una app de notas")

        XCTAssertEqual(intent.action, .createMemory)
        XCTAssertNotNil(intent.title)
    }

    func testMemoriaKeywordCreatesMemoryInsteadOfAChatReply() {
        let intent = parser.parse("Memoria: visitar Cusco cuando tenga vacaciones")

        XCTAssertEqual(intent.action, .createMemory)
        XCTAssertEqual(intent.title, "visitar Cusco cuando tenga vacaciones")
    }

    func testAcuérdatePhraseRemovesRelativeTimeFromReminderTitle() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let intent = parser.parse("Acuérdate de sacar a los perros dentro de un minuto", now: now)

        XCTAssertEqual(intent.action, .createReminder)
        XCTAssertEqual(intent.title, "sacar a los perros")
        XCTAssertEqual(try XCTUnwrap(intent.date).timeIntervalSince(now), 60, accuracy: 0.01)
    }

    func testTaskChecklistRoundTripsWithDescriptionAndCompletionState() throws {
        let items = [
            WidgetChecklistItem(id: "paso-1", title: "Comprar ingredientes", isCompleted: true),
            WidgetChecklistItem(id: "paso-2", title: "Preparar la cena", isCompleted: false)
        ]
        let stored = try XCTUnwrap(TaskChecklistCodec.encode(description: "Cena familiar", items: items))
        let decoded = TaskChecklistCodec.decode(stored)

        XCTAssertEqual(decoded.description, "Cena familiar")
        XCTAssertEqual(decoded.items, items)
    }

    func testParseTaskIntent() {
        let intent = parser.parse("Crear una tarea: llamar al médico")

        XCTAssertEqual(intent.action, .createTask)
        XCTAssertNotNil(intent.title)
    }

    func testParseSearchIntent() {
        let intent = parser.parse("¿Qué tengo anotado sobre proyectos?")

        XCTAssertEqual(intent.action, .searchMemory)
        XCTAssertEqual(intent.title, "proyectos")
    }

    func testAccentedReminderParsesTimeWithoutGuessing() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Lima")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 10))!
        let localParser = IntentParser(calendar: calendar)

        let clear = localParser.parse("Recuérdame comprar pañales mañana a las 7 de la tarde", now: now)
        XCTAssertEqual(clear.action, .createReminder)
        XCTAssertEqual(clear.title, "comprar pañales")
        XCTAssertEqual(calendar.component(.hour, from: clear.date!), 19)

        let ambiguous = localParser.parse("Recuérdame comprar pañales mañana a las 7", now: now)
        XCTAssertNil(ambiguous.date)
    }

    func testReminderParsesSpokenSpanishHourAndKeepsCleanTitle() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Lima")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 16, minute: 49))!
        let localParser = IntentParser(calendar: calendar)

        let intent = localParser.parse("Recuérdame sacar a los perros hoy a las seis de la tarde", now: now)

        XCTAssertEqual(intent.action, .createReminder)
        XCTAssertEqual(intent.title, "sacar a los perros")
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(intent.date)), 18)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(intent.date)), 17)
    }

    func testPasadoMananaIsTwoDaysAhead() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Lima")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 10))!
        let intent = IntentParser(calendar: calendar).parse("Recuérdame llamar a Ana pasado mañana a las nueve de la mañana", now: now)

        XCTAssertEqual(intent.title, "llamar a Ana")
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(intent.date)), 19)
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(intent.date)), 9)
    }

    func testMorningTimeWithoutDayDoesNotInventTomorrow() {
        let intent = parser.parse("Recuérdame comprar pan a las nueve de la mañana")

        XCTAssertEqual(intent.title, "comprar pan")
        XCTAssertNil(intent.date)
    }

    func testRelativeReminderUnderstandsOneMinuteAndCommandAtEnd() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let intent = parser.parse("Dentro de un minuto recuérdame lavar mi polo", now: now)

        XCTAssertEqual(intent.title, "lavar mi polo")
        XCTAssertEqual(try XCTUnwrap(intent.date).timeIntervalSince(now), 60, accuracy: 0.01)
    }

    func testRelativeReminderUnderstandsMinutesHoursAndHalfHour() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let minutes = parser.parse("Recuérdame llamar a mamá en quince minutos", now: now)
        XCTAssertEqual(minutes.title, "llamar a mamá")
        XCTAssertEqual(try XCTUnwrap(minutes.date).timeIntervalSince(now), 15 * 60, accuracy: 0.01)

        let halfHour = parser.parse("Recuérdame tomar agua dentro de media hora", now: now)
        XCTAssertEqual(halfHour.title, "tomar agua")
        XCTAssertEqual(try XCTUnwrap(halfHour.date).timeIntervalSince(now), 30 * 60, accuracy: 0.01)

        let hours = parser.parse("Recuérdame revisar el horno dentro de dos horas", now: now)
        XCTAssertEqual(hours.title, "revisar el horno")
        XCTAssertEqual(try XCTUnwrap(hours.date).timeIntervalSince(now), 2 * 60 * 60, accuracy: 0.01)
    }

    func testCreateReminderPhraseDoesNotBecomeItsOwnNotificationTitle() {
        let intent = parser.parse("Crea un recordatorio para apagar la PC dentro de dos horas")

        XCTAssertEqual(intent.action, .createReminder)
        XCTAssertEqual(intent.title, "apagar la PC")
        XCTAssertEqual(try XCTUnwrap(intent.date).timeIntervalSinceNow, 2 * 60 * 60, accuracy: 3)
    }

    func testRelativeReminderSupportsSecondsMonthsAndHalfHours() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let seconds = parser.parse("Recuérdame cerrar la puerta dentro de treinta segundos", now: now)
        XCTAssertEqual(try XCTUnwrap(seconds.date).timeIntervalSince(now), 30, accuracy: 0.01)

        let halfHours = parser.parse("Recuérdame salir dentro de dos horas y media", now: now)
        XCTAssertEqual(try XCTUnwrap(halfHours.date).timeIntervalSince(now), 2.5 * 60 * 60, accuracy: 0.01)
        XCTAssertEqual(halfHours.title, "salir")

        XCTAssertEqual(parser.parse("Alarma fuerte mañana a las seis", now: now).action, .strongAlarm)
    }

    func testReminderUnderstandsUpcomingWeekdayAndClockPhrase() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Lima")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 10))!
        let localParser = IntentParser(calendar: calendar)
        let intent = localParser.parse("Recuérdame llamar a mi mamá el lunes a las cinco y media de la tarde", now: now)

        XCTAssertEqual(intent.title, "llamar a mi mamá")
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(intent.date)), 19)
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(intent.date)), 17)
        XCTAssertEqual(calendar.component(.minute, from: try XCTUnwrap(intent.date)), 30)
    }

    func testReminderUnderstandsThisAfternoon() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Lima")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 10))!
        let intent = IntentParser(calendar: calendar).parse("Recuérdame regar las plantas esta tarde a las ocho", now: now)

        XCTAssertEqual(intent.title, "regar las plantas")
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(intent.date)), 20)
    }

    func testUnknownTextIsNotTreatedAsMemorySearch() {
        XCTAssertEqual(parser.parse("Cuéntame algo curioso").action, .unknown)
    }
}
