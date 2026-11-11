import Foundation
import Testing
@testable import House_Lights_Watch_App

struct GroupedLightCommandTests {
    private func json(_ c: GroupedLightCommand) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as! [String: Any]
    }

    @Test func encodesHueV2Shape() throws {
        let body = try json(GroupedLightCommand(on: true, brightness: 42, mirek: 300))
        #expect((body["on"] as? [String: Bool])?["on"] == true)
        #expect((body["dimming"] as? [String: Double])?["brightness"] == 42)
        #expect((body["color_temperature"] as? [String: Int])?["mirek"] == 300)
        #expect(body["color"] == nil)
    }

    @Test func encodesXY() throws {
        let body = try json(GroupedLightCommand(xy: XY(x: 0.3, y: 0.4)))
        let xy = (body["color"] as? [String: Any])?["xy"] as? [String: Double]
        #expect(xy?["x"] == 0.3)
        #expect(xy?["y"] == 0.4)
        #expect(body["on"] == nil)
    }

    @Test func brightnessIsKeptAboveZero() throws {
        let body = try json(GroupedLightCommand(brightness: 0))
        #expect((body["dimming"] as? [String: Double])?["brightness"] == 1)
    }

    @Test func newerValuesWin() {
        let merged = GroupedLightCommand(on: true, brightness: 40).merged(with: GroupedLightCommand(brightness: 55))
        #expect(merged == GroupedLightCommand(on: true, brightness: 55))
    }

    @Test func colorAndWarmthReplaceEachOther() {
        let a = GroupedLightCommand(mirek: 300).merged(with: GroupedLightCommand(xy: XY(x: 0.2, y: 0.2)))
        #expect(a.mirek == nil && a.xy != nil)
        let b = a.merged(with: GroupedLightCommand(mirek: 250))
        #expect(b.mirek == 250 && b.xy == nil)
    }

    @Test func turningOffDropsBrightnessAndColor() {
        let merged = GroupedLightCommand(on: true, brightness: 40, mirek: 300).merged(with: .power(false))
        #expect(merged == GroupedLightCommand(on: false))
    }
}
