import XCTest

final class NotificationFlowTests: XCTestCase {
    func testTaskDictationComesFirst() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Tareas"].waitForExistence(timeout: 15))
        app.buttons["Tareas"].tap()
        app.buttons["Nueva tarea"].tap()
        let microphone = app.buttons["Dictar pendientes"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        let step = app.textFields["Escribe un paso"]
        XCTAssertLessThan(microphone.frame.minY, step.frame.minY)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Tarea — dictado primero"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Cancelar"].tap()
        app.buttons["Cerrar"].tap()
    }

    func testTapNotificationOpensDetailAndSnoozes() throws {
        let app = XCUIApplication()
        app.launch()
        let field = app.textFields["Escribe lo que necesitas…"]
        let multiline = app.textViews.firstMatch
        XCTAssertTrue(app.buttons["Enviar al chat"].waitForExistence(timeout: 15))
        let input = field.exists ? field : multiline
        input.tap()
        input.typeText("Recuérdame validar aviso Lenara dentro de veinte segundos")
        app.buttons["Enviar al chat"].tap()
        let confirmed = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Recordatorio creado para")).firstMatch
        XCTAssertTrue(confirmed.waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notification = springboard.otherElements.containing(NSPredicate(format: "label CONTAINS[c] %@", "validar aviso Lenara")).firstMatch
        XCTAssertTrue(notification.waitForExistence(timeout: 35))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Notificación nueva — icono"
        shot.lifetime = .keepAlways
        add(shot)
        notification.tap()
        XCTAssertTrue(app.staticTexts["Programado para"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Creado"].exists)
        let detail = XCTAttachment(screenshot: app.screenshot())
        detail.name = "Detalle desde notificación"
        detail.lifetime = .keepAlways
        add(detail)
        let custom = app.textFields["Minutos"]
        custom.tap()
        custom.typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + "1")
        app.swipeUp()
        app.buttons["Posponer 1 minutos"].tap()
        XCTAssertTrue(app.buttons["Tareas"].waitForExistence(timeout: 8))
    }
}
