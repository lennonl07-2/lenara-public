import XCTest
import UIKit

final class LockIconTests: XCTestCase {
    @MainActor func testLogoExistsInAppAndWidgetBundles() throws {
        let pluginURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL?.appendingPathComponent("LenaraWidgets.appex"))
        let widgetBundle = try XCTUnwrap(Bundle(url: pluginURL))
        for bundle in [Bundle.main, widgetBundle] {
            let symbol = try XCTUnwrap(UIImage(named: "LenaraLockSymbol", in: bundle, compatibleWith: nil), bundle.bundlePath)
            XCTAssertTrue(symbol.isSymbolImage)
            let png = try XCTUnwrap(UIImage(named: "LenaraLockLogo", in: bundle, compatibleWith: nil), bundle.bundlePath)
            XCTAssertFalse(png.isSymbolImage)
            XCTAssertEqual(png.size.width, 1254)
            XCTAssertEqual(png.size.height, 1254)
        }
    }

    @MainActor func testControlSymbolRendersAtEveryScale() throws {
        let pluginURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL?.appendingPathComponent("LenaraWidgets.appex"))
        let bundle = try XCTUnwrap(Bundle(url: pluginURL))
        let symbol = try XCTUnwrap(UIImage(named: "LenaraLockSymbol", in: bundle, compatibleWith: nil))
        XCTAssertTrue(symbol.isSymbolImage)
        let scales: [UIImage.SymbolScale] = [.small, .medium, .large]
        let weights: [UIImage.SymbolWeight] = [.regular, .medium, .semibold]
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300), format: format)
        let preview = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
            for (row, scale) in scales.enumerated() {
                for (column, weight) in weights.enumerated() {
                    let configured = symbol.applyingSymbolConfiguration(.init(pointSize: 40, weight: weight, scale: scale))!
                        .withTintColor(.white, renderingMode: .alwaysOriginal)
                    print("LENARA_SYMBOL scale=\(scale.rawValue) weight=\(weight.rawValue) size=\(configured.size)")
                    configured.draw(in: CGRect(x: column * 100 + 20, y: row * 100 + 20, width: 60, height: 60))
                }
            }
        }
        let attachment = XCTAttachment(image: preview)
        attachment.name = "Lenara symbol — three scales and weights"
        attachment.lifetime = .keepAlways
        add(attachment)
        let cg = try XCTUnwrap(preview.cgImage)
        let bytes = try XCTUnwrap(cg.dataProvider?.data) as Data
        // Detect a compiled asset whose symbol geometry is blank at runtime.
        let visible = stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] > 100 }.count
        XCTAssertGreaterThan(visible, 1000)
    }
}
