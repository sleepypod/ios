import Testing
import Foundation
@testable import Sleepypod

@Suite("ThermalBed")
struct ThermalBedTests {

    @Test("Ramp hits its stops and clamps at the ends")
    func rampStops() {
        let cool = TempRamp.rgb(64)
        #expect(abs(cool.r - 60.0 / 255) < 1e-9 && abs(cool.b - 165.0 / 255) < 1e-9)
        #expect(TempRamp.rgb(40) == TempRamp.rgb(64))
        #expect(TempRamp.rgb(120) == TempRamp.rgb(97))
        #expect(TempRamp.rgb(nil) == TempRamp.rgb(80.5))
        #expect(TempRamp.rgb(.nan) == TempRamp.rgb(80.5))
    }

    @Test("Ramp interpolates between stops")
    func rampInterpolates() {
        let mid = TempRamp.rgb((80.5 + 97) / 2)
        #expect(abs(mid.r - (78 + 180) / 2.0 / 255) < 1e-9)
    }

    @Test("Zones read outer, center, inner in °F and drop sentinels")
    func zonesFromSide() {
        let side = BedTempSide(amb: 22, hu: 40, temps: [30, -327.68, 25, 0])
        let zones = ThermalZones.fahrenheit(side)
        #expect(zones.count == 3)
        #expect(zones[0] == 86)
        #expect(zones[1] == nil)
        #expect(zones[2] == 77)
        #expect(ThermalZones.fahrenheit(nil) == ThermalZones.none)
    }

    @Test("Texture key changes only on half-degree moves or missing readings")
    func heatKey() {
        let base = HeatTexture.key([86.0, 87.0, 85.0])
        #expect(HeatTexture.key([86.1, 87.0, 85.0]) == base)
        #expect(HeatTexture.key([86.6, 87.0, 85.0]) != base)
        #expect(HeatTexture.key([nil, 87.0, 85.0]) != base)
    }

    @Test("Missing zones paint the cover grey")
    func missingIsCover() {
        let colors = HeatTexture.zoneColors(ThermalZones.none)
        #expect(colors.allSatisfy { $0 == HeatTexture.cover })
    }
}
