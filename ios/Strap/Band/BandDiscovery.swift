import Foundation

/// One strap seen during a discovery pass. `id` is the CoreBluetooth
/// peripheral identifier, which is stable per phone and survives relaunches —
/// two bands of the same model advertise the same name, so the identifier is
/// the only thing that tells them apart.
struct DiscoveredBand: Identifiable, Equatable {
    let id: String
    let uuid: UUID
    let name: String
    let rssi: Int
    let lastSeenUnix: Int
}

enum BandDiscovery {
    /// Fold a fresh sighting into the list: same identifier replaces the old
    /// row (name and signal move), and only the `limit` strongest survive so a
    /// crowded room cannot grow the picker without bound.
    static func merge(
        _ existing: [DiscoveredBand],
        adding band: DiscoveredBand,
        limit: Int = 8
    ) -> [DiscoveredBand] {
        var updated = existing.filter { $0.id != band.id }
        updated.append(band)
        let ordered = updated.sorted { left, right in
            if left.rssi != right.rssi { return left.rssi > right.rssi }
            return left.name < right.name
        }
        return Array(ordered.prefix(max(1, limit)))
    }
}
