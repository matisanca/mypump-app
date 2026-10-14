import Foundation
import Testing
@testable import MyPumpReglas

/// `new Date(iso)` de V8 (node 26), con los bordes que el port leía distinto: lo encontró el gemelo de Android
/// (6de8c9c). nil es "Invalid Date". Las que no traen zona van en hora local y se comparan con el calendario de acá.
@Suite("FechaJS como V8")
struct FechaJSTests {
    @Test(arguments: [
        ("2026-10-04T24:30:00Z", nil),
        ("2026-10-04T24:00:00Z", 1_791_158_400_000),
        ("2026-10-04T24:00:00.000Z", 1_791_158_400_000),
        ("2026-10-04T24:00:00.001Z", nil),
        ("2026-10-04T24:00Z", 1_791_158_400_000),
        ("2026-10-04T10:00:00+19:00", 1_791_039_600_000),
        ("2026-10-04T10:00:00-20:30", 1_791_181_800_000),
        ("2026-10-04T10:00:00+18:00", 1_791_043_200_000),
        ("2026-10-04T10:00:00+23:59", 1_791_021_660_000),
        ("2026-10-04T10:00:00+24:00", nil),
        ("2026-10-04T10:00:00+99:00", nil),
        ("2026-10-04T10:00:00+05:60", nil),
        ("2026-10-04T10:00:00+05", nil),
        ("2026-02-31", 1_772_496_000_000),
        ("2026-02-31T10:00:00Z", 1_772_532_000_000),
        ("2026-02-32", nil),
        ("2026-10-04T10:00Z", 1_791_108_000_000),
        ("2026-10-04T10:00:00.5+00:00", 1_791_108_000_500),
        ("2026-10-04T10:00:00.1234567Z", 1_791_108_000_123),
        ("2026-10-04T10:00:00,123Z", nil),
        ("2026-10-04T10:00:00+0530", 1_791_088_200_000),
        ("2026-10-04T10:00:60Z", nil),
        ("2026-10-04T10:60:00Z", nil),
        ("2026-10-04T10:00:00.Z", nil),
        ("2026-10-04T22:32:00.123456+00:00", 1_791_153_120_123),
    ] as [(String, Double?)])
    func comoV8(_ iso: String, _ esperado: Double?) {
        #expect(FechaJS.leer(iso).map { ($0.timeIntervalSince1970 * 1000).rounded() } == esperado, "\(iso)")
    }

    @Test func sinZonaEsHoraLocal() {
        let local = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 10))
        #expect(FechaJS.leer("2026-10-04 10:00:00") == local)
        #expect(FechaJS.leer("2026-10-04T10:00:00") == local)
    }
}
