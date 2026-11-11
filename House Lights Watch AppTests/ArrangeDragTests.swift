import CoreGraphics
import Foundation
import Testing
@testable import House_Lights_Watch_App

/// The four Arrange drag rules (SPEC.md › Arrange drag rules).
struct ArrangeDragTests {
    let layout = GridLayout(columns: 3, tile: 50, spacing: 6, scrolls: false)   // slots at 0, 56, 112
    let order = ["a", "b", "c", "d", "e", "f"]
    let t0 = Date(timeIntervalSince1970: 1000)

    func center(_ i: Int) -> CGPoint { let f = layout.frame(of: i); return CGPoint(x: f.midX, y: f.midY) }

    @Test func startsOnTheTileUnderTheFinger() throws {
        let drag = try #require(ArrangeDrag(order: order, layout: layout, at: center(4)))
        #expect(drag.draggedID == "e")
        #expect(ArrangeDrag(order: order, layout: layout, at: CGPoint(x: 53, y: 10)) == nil)   // the gap between tiles
    }

    @Test func switchesOnlyInTheMiddleSixtyPercent() throws {
        var drag = try #require(ArrangeDrag(order: order, layout: layout, at: center(0)))
        // Slot 1 spans x 56…106; its middle 60% is 66…96.
        let r1 = drag.move(to: CGPoint(x: 60, y: 25), now: t0)
        #expect(!r1)    // edge of slot 1: no candidate
        #expect(drag.candidate == nil)
        let r2 = drag.move(to: CGPoint(x: 70, y: 25), now: t0)
        #expect(r2)     // inside the middle
        #expect(drag.candidate == 1)
    }

    @Test func waitsAboutOneHundredFiftyMillisecondsBeforeMoving() throws {
        var drag = try #require(ArrangeDrag(order: order, layout: layout, at: center(0)))
        drag.move(to: center(2), now: t0)
        let r3 = drag.commitIfDue(now: t0.addingTimeInterval(0.1))
        #expect(!r3)
        #expect(drag.order == order)
        let r4 = drag.commitIfDue(now: t0.addingTimeInterval(0.15))
        #expect(r4)
        #expect(drag.order == ["b", "c", "a", "d", "e", "f"])
        #expect(drag.target == 2)
    }

    @Test func passingThroughASlotDoesNotMoveTiles() throws {
        var drag = try #require(ArrangeDrag(order: order, layout: layout, at: center(0)))
        drag.move(to: center(1), now: t0)                          // over b…
        drag.move(to: center(2), now: t0.addingTimeInterval(0.05)) // …then on to c within 150 ms
        let r5 = drag.commitIfDue(now: t0.addingTimeInterval(0.16))
        #expect(!r5)   // b's wait was replaced
        let r6 = drag.commitIfDue(now: t0.addingTimeInterval(0.21))
        #expect(r6)
        #expect(drag.order == ["b", "c", "a", "d", "e", "f"])
    }

    @Test func leavingTheCandidateBeforeTheWaitCancelsTheMove() throws {
        var drag = try #require(ArrangeDrag(order: order, layout: layout, at: center(0)))
        drag.move(to: center(1), now: t0)
        drag.move(to: CGPoint(x: 109, y: 25), now: t0.addingTimeInterval(0.05))   // into the gap
        let r7 = drag.commitIfDue(now: t0.addingTimeInterval(0.2))
        #expect(!r7)
        #expect(drag.order == order)
    }

    @Test func hitTestingUsesFixedSlotsNotTheMovingTiles() throws {
        // After a move, the slots stay where they were: the finger over slot 0 means slot 0,
        // whichever tile is drawn there now.
        var drag = try #require(ArrangeDrag(order: order, layout: layout, at: center(0)))
        drag.move(to: center(1), now: t0)
        let r8 = drag.commitIfDue(now: t0.addingTimeInterval(0.2))
        #expect(r8)
        #expect(drag.order == ["b", "a", "c", "d", "e", "f"])
        drag.move(to: center(0), now: t0.addingTimeInterval(0.3))
        let r9 = drag.commitIfDue(now: t0.addingTimeInterval(0.5))
        #expect(r9)
        #expect(drag.order == order)
    }

    @Test func returningToItsOwnSlotCancelsTheCandidate() throws {
        var drag = try #require(ArrangeDrag(order: order, layout: layout, at: center(0)))
        drag.move(to: center(1), now: t0)
        drag.move(to: center(0), now: t0.addingTimeInterval(0.05))
        #expect(drag.candidate == nil)
        let r10 = drag.commitIfDue(now: t0.addingTimeInterval(0.3))
        #expect(!r10)
    }

    @Test func arrangeFitsManyRoomsWithoutScrolling() {
        let l = GridLayout.fitting(count: 12, width: 190, height: 150)
        #expect(l.columns == 3 && !l.scrolls)
        #expect(l.height(count: 12) <= 150)
    }

    @Test @MainActor func savedOrderIsUsedByTheGridAndNewRoomsGoLast() async {
        let (app, _) = ConnectionTests.makeApp(paired: true)
        await app.start()
        app.saveOrder(["mock-room-4", "mock-room-0"])
        #expect(app.rooms.prefix(2).map(\.id) == ["mock-room-4", "mock-room-0"])
        #expect(app.rooms.count == 6)
    }
}
