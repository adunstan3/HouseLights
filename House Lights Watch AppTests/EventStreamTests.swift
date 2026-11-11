import Foundation
import Testing
@testable import House_Lights_Watch_App

struct EventStreamTests {
    /// Shaped like the Hue bridge's /eventstream/clip/v2 output.
    static let sample = """
    : hi

    id: 1700000000:0
    data: [{"creationtime":"2026-11-11T10:00:00Z","data":[{"id":"gl-1","id_v1":"/groups/1","on":{"on":false},"owner":{"rid":"room-1","rtype":"room"},"type":"grouped_light"}],"id":"e1","type":"update"}]

    id: 1700000001:0\r
    data: [{"creationtime":"2026-11-11T10:00:01Z","data":[{"id":"light-1","type":"light","dimming":{"brightness":42.5},"color":{"xy":{"x":0.45,"y":0.41}},"color_temperature":{"mirek":null,"mirek_valid":false},"owner":{"rid":"dev-1","rtype":"device"}}],"id":"e2","type":"update"}]\r
    \r

    """

    @Test func splitsEventsOnBlankLines() throws {
        var parser = EventStreamParser()
        let messages = parser.feed(Array(Self.sample.utf8))
        #expect(messages.count == 2)
        let first = try EventStreamParser.decode(messages[0])
        #expect(first.first?.type == "update")
        #expect(first.first?.data.first?.on == HueOn(on: false))
    }

    @Test func decodesPartialLightUpdates() throws {
        var parser = EventStreamParser()
        let messages = parser.feed(Array(Self.sample.utf8))
        let item = try #require(try EventStreamParser.decode(messages[1]).first?.data.first)
        #expect(item.type == "light")
        #expect(item.dimming?.brightness == 42.5)
        #expect(item.color?.xy == HueXY(x: 0.45, y: 0.41))
        #expect(item.color_temperature?.mirek_valid == false)
    }

    @Test func ignoresCommentsAndIncompleteEvents() {
        var parser = EventStreamParser()
        #expect(parser.feed(Array(": keep-alive\n\n".utf8)).isEmpty)
        #expect(parser.feed(Array("data: [1]\n".utf8)).isEmpty)   // not finished yet
        #expect(parser.feed(Array("\n".utf8)) == ["[1]"])
    }

    @Test func joinsMultiLineData() {
        var parser = EventStreamParser()
        #expect(parser.feed(Array("data: a\ndata: b\n\n".utf8)) == ["a\nb"])
    }
}
