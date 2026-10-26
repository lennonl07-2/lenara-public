import XCTest
@testable import Lenara

final class LocalModelCatalogTests: XCTestCase {
    func testOffersThreePinnedModelsWithinRequestedSizeRange() {
        let models = LocalModel.catalog
        XCTAssertGreaterThanOrEqual(models.count, 3)
        XCTAssertEqual(Set(models.map(\.id)).count, models.count)
        for model in models {
            XCTAssertGreaterThanOrEqual(model.bytes, 400_000_000)
            XCTAssertLessThanOrEqual(model.bytes, 700_000_000)
            XCTAssertEqual(model.sha256.count, 64)
            XCTAssertEqual(model.revision.count, 40)
            XCTAssertEqual(model.license, "Apache-2.0")
        }
    }
}
