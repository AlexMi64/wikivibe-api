import XCTest
@testable import Codenotch

final class AccountWindowLayoutTests: XCTestCase {
    func testLegacyWidgetCardIsRemovedWithoutResettingLayout() throws {
        let saved = Data("""
        {"arrangement":"horizontal","density":"compact",
         "order":["apiKeys","appearance","balance","account"],"hidden":["appearance","balance"]}
        """.utf8)

        var layout = try JSONDecoder().decode(AccountWindowLayout.self, from: saved)
        XCTAssertEqual(layout.arrangement, .horizontal)
        XCTAssertEqual(layout.density, .compact)
        XCTAssertEqual(layout.orderedCards, [.apiKeys, .balance, .account])
        XCTAssertEqual(layout.visibleCards, [.apiKeys, .account])

        layout.move(.account, by: -1)
        let persisted = try JSONDecoder().decode(AccountWindowLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(persisted.orderedCards, [.apiKeys, .account, .balance])
        XCTAssertEqual(persisted.visibleCards, [.apiKeys, .account])
    }
}
