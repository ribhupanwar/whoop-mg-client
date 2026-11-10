import Foundation
import XCTest
@testable import Strap

private func band(
    _ id: String, name: String = "WHOOP MG", rssi: Int, at second: Int = 0
) -> DiscoveredBand {
    DiscoveredBand(
        id: id,
        uuid: UUID(uuidString: id) ?? UUID(),
        name: name,
        rssi: rssi,
        lastSeenUnix: second
    )
}

final class BandDiscoveryTests: XCTestCase {
    private let idA = "AAAAAAAA-0000-0000-0000-000000000001"
    private let idB = "BBBBBBBB-0000-0000-0000-000000000002"

    func testSameIdentifierReplacesTheRow() {
        let first = BandDiscovery.merge([], adding: band(idA, rssi: -70, at: 1))
        let second = BandDiscovery.merge(
            first, adding: band(idA, name: "WHOOP MG", rssi: -40, at: 2)
        )
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.rssi, -40)
        XCTAssertEqual(second.first?.lastSeenUnix, 2)
    }

    func testTwoBandsStaySeparate() {
        var bands = BandDiscovery.merge([], adding: band(idA, rssi: -60))
        bands = BandDiscovery.merge(bands, adding: band(idB, rssi: -75))
        XCTAssertEqual(bands.count, 2)
        XCTAssertEqual(Set(bands.map(\.id)), [idA, idB])
    }

    func testStrongestSignalComesFirst() {
        var bands = BandDiscovery.merge([], adding: band(idA, rssi: -80))
        bands = BandDiscovery.merge(bands, adding: band(idB, rssi: -45))
        XCTAssertEqual(bands.map(\.id), [idB, idA])
    }

    func testLimitKeepsTheStrongest() {
        var bands: [DiscoveredBand] = []
        for index in 0..<12 {
            let id = UUID().uuidString
            bands = BandDiscovery.merge(
                bands,
                adding: band(id, name: "WHOOP \(index)", rssi: -90 + index),
                limit: 4
            )
        }
        XCTAssertEqual(bands.count, 4)
        XCTAssertEqual(bands.map(\.rssi), [-79, -80, -81, -82])
    }
}
