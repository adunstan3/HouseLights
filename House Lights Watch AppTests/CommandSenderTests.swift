import Foundation
import Testing
@testable import House_Lights_Watch_App

@MainActor
struct CommandSenderTests {
    final class Recorder { var sent: [(String, GroupedLightCommand, ContinuousClock.Instant)] = [] }

    @Test func sendsFirstAtOnceThenOnlyTheLatest() async throws {
        let rec = Recorder()
        let sender = CommandSender(interval: .milliseconds(200)) { id, c in rec.sent.append((id, c, .now)) }
        sender.enqueue(GroupedLightCommand(brightness: 10), to: "a")
        try await Task.sleep(for: .milliseconds(20))
        sender.enqueue(GroupedLightCommand(brightness: 20), to: "a")
        sender.enqueue(GroupedLightCommand(brightness: 30), to: "a")
        sender.enqueue(GroupedLightCommand(brightness: 40), to: "a")
        try await Task.sleep(for: .milliseconds(400))
        #expect(rec.sent.map(\.1.brightness) == [10, 40])
        let gap = rec.sent[1].2 - rec.sent[0].2
        #expect(gap >= .milliseconds(180))
    }

    @Test func roomsAreThrottledSeparately() async throws {
        let rec = Recorder()
        let sender = CommandSender(interval: .milliseconds(500)) { id, c in rec.sent.append((id, c, .now)) }
        sender.enqueue(.power(true), to: "a")
        sender.enqueue(.power(true), to: "b")
        try await Task.sleep(for: .milliseconds(50))
        #expect(Set(rec.sent.map(\.0)) == ["a", "b"])
    }

    @Test func mergesQueuedFields() async throws {
        let rec = Recorder()
        let sender = CommandSender(interval: .milliseconds(150)) { id, c in rec.sent.append((id, c, .now)) }
        sender.enqueue(GroupedLightCommand(brightness: 10), to: "a")
        try await Task.sleep(for: .milliseconds(20))
        sender.enqueue(.power(true), to: "a")
        sender.enqueue(GroupedLightCommand(brightness: 70), to: "a")
        #expect(sender.isPending("a"))
        try await Task.sleep(for: .milliseconds(300))
        #expect(rec.sent.last?.1 == GroupedLightCommand(on: true, brightness: 70))
        #expect(!sender.isPending("a"))
    }
}
