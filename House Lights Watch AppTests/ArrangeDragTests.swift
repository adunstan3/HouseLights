import CoreGraphics
import Foundation
import Testing
@testable import House_Lights_Watch_App

/// Free placement: rooms anywhere on the grid (gaps kept), including half-way between columns.
struct GridArrangementTests {
    let ids = ["a", "b", "c", "d", "e", "f"]

    func s(_ row: Int, _ half: Int) -> Slot { Slot(row: row, half: half) }

    @Test func roomsStartPackedInReadingOrder() {
        let g = GridArrangement.make(roomIDs: ids, saved: nil)
        #expect(g.columns == 3)
        #expect(g.slots["a"] == s(0, 0) && g.slots["c"] == s(0, 4) && g.slots["d"] == s(1, 0))
        #expect(g.readingOrder == ids)
        #expect(GridArrangement.make(roomIDs: ["a", "b", "c"], saved: nil).columns == 2)
    }

    @Test func savedSpotsAreKeptWithGapsAndNewRoomsFillTheFirstFreeSpot() {
        let saved = GridArrangement(columns: 3, slots: ["a": s(2, 4), "b": s(0, 1)])
        let g = GridArrangement.make(roomIDs: ["a", "b", "c", "d", "e"], saved: saved)
        #expect(g.slots["a"] == s(2, 4))            // no compacting to the top left
        #expect(g.slots["b"] == s(0, 1))            // half-way spot kept
        #expect(g.slots["c"] == s(0, 4))            // row 0: half 0 and 2 overlap b at 1
        #expect(g.slots["d"] == s(1, 0))
    }

    @Test func switchingBetweenTwoAndThreeAcrossStartsAfresh() {
        let saved = GridArrangement(columns: 2, slots: ["a": s(1, 2), "b": s(0, 0)])
        let g = GridArrangement.make(roomIDs: ids, saved: saved)
        #expect(g.columns == 3)
        #expect(g.slots["a"] == s(0, 0))
    }

    @Test func roomsInTheWayGoToTheNearestFreeSpot() {
        let g = GridArrangement.make(roomIDs: ids, saved: nil)       // row 2 is empty
        let moved = g.placing("f", at: s(0, 2), rows: 3)              // f onto b
        #expect(moved.slots["f"] == s(0, 2))
        #expect(moved.slots["b"] == s(1, 4))                          // f's old spot is nearest
        #expect(moved.slots["a"] == s(0, 0) && moved.slots["c"] == s(0, 4))   // nobody else moves
    }

    @Test func aHalfWayDropPushesBothNeighboursAside() {
        let g = GridArrangement.make(roomIDs: ids, saved: nil)
        let moved = g.placing("f", at: s(0, 1), rows: 3)              // between a and b
        #expect(moved.slots["f"] == s(0, 1))
        for id in ["a", "b", "c", "d", "e"] {
            if let other = moved.slots[id] { #expect(!GridArrangement.overlap(other, s(0, 1)), "\(id) overlaps") }
        }
        #expect(Set(moved.slots.values).count == 6)
    }

    @Test func aNewRowIsUsedOnlyWhenNothingIsFree() {
        let nine = (0..<9).map { "r\($0)" }
        let g = GridArrangement.make(roomIDs: nine, saved: nil)
        let moved = g.placing("r8", at: s(0, 1), rows: 3)             // nowhere left on screen
        #expect(moved.rowsUsed == 4)
    }
}

/// The four Arrange drag rules (SPEC.md › Arrange drag rules), with free placement.
struct ArrangeDragTests {
    let layout = GridLayout(columns: 3, tile: 50, spacing: 6, scrolls: false)   // halfStep 28, rowStep 56
    let start = GridArrangement.make(roomIDs: ["a", "b", "c", "d", "e", "f"], saved: nil)
    let t0 = Date(timeIntervalSince1970: 1000)

    /// The centre of a slot on screen.
    func p(_ row: Int, _ half: Int) -> CGPoint { CGPoint(x: CGFloat(half) * 28 + 25, y: CGFloat(row) * 56 + 25) }

    @Test func startsOnTheRoomUnderTheFinger() throws {
        let drag = try #require(ArrangeDrag(arrangement: start, layout: layout, rows: 3, at: p(1, 2)))
        #expect(drag.draggedID == "e")
        #expect(ArrangeDrag(arrangement: start, layout: layout, rows: 3, at: p(2, 0)) == nil)   // empty spot
    }

    @Test func aSpotIsTargetedOnlyFromTheMiddleOfItsCell() throws {
        var drag = try #require(ArrangeDrag(arrangement: start, layout: layout, rows: 3, at: p(0, 0)))
        var edge = p(2, 2); edge.x += 12                              // 0.43 of a half-step off centre
        let early = drag.move(to: edge, now: t0)
        #expect(!early && drag.candidate == nil)
        let ok = drag.move(to: p(2, 2), now: t0)
        #expect(ok && drag.candidate == Slot(row: 2, half: 2))
    }

    @Test func otherRoomsMoveOnlyAfterTheWait() throws {
        var drag = try #require(ArrangeDrag(arrangement: start, layout: layout, rows: 3, at: p(0, 0)))
        drag.move(to: p(0, 2), now: t0)                               // over b
        let tooSoon = drag.commitIfDue(now: t0.addingTimeInterval(0.1))
        #expect(!tooSoon && drag.arrangement == start)
        let moved = drag.commitIfDue(now: t0.addingTimeInterval(0.15))
        #expect(moved)
        #expect(drag.arrangement.slots["a"] == Slot(row: 0, half: 2))
        #expect(drag.arrangement.slots["b"] == Slot(row: 0, half: 0))  // into a's old spot
    }

    @Test func roomsPassedOverGoBackWhereTheyWere() throws {
        var drag = try #require(ArrangeDrag(arrangement: start, layout: layout, rows: 3, at: p(0, 0)))
        drag.move(to: p(0, 2), now: t0)
        _ = drag.commitIfDue(now: t0.addingTimeInterval(0.2))          // b moved aside
        drag.move(to: p(2, 2), now: t0.addingTimeInterval(0.3))        // on to an empty spot
        _ = drag.commitIfDue(now: t0.addingTimeInterval(0.5))
        #expect(drag.arrangement.slots["b"] == Slot(row: 0, half: 2))  // b is back
        #expect(drag.arrangement.slots["a"] == Slot(row: 2, half: 2))
    }

    @Test func halfWaySpotsCanBeChosen() throws {
        var drag = try #require(ArrangeDrag(arrangement: start, layout: layout, rows: 3, at: p(1, 4)))
        drag.move(to: p(2, 1), now: t0)
        _ = drag.commitIfDue(now: t0.addingTimeInterval(0.2))
        #expect(drag.arrangement.slots["f"] == Slot(row: 2, half: 1))
    }

    @Test func leavingTheCandidateBeforeTheWaitCancelsIt() throws {
        var drag = try #require(ArrangeDrag(arrangement: start, layout: layout, rows: 3, at: p(0, 0)))
        drag.move(to: p(2, 4), now: t0)
        drag.move(to: p(2, 0), now: t0.addingTimeInterval(0.05))       // somewhere else, before 150 ms
        _ = drag.commitIfDue(now: t0.addingTimeInterval(0.16))
        #expect(drag.arrangement.slots["a"] != Slot(row: 2, half: 4))
    }

    @Test @MainActor func savedArrangementIsWhatTheGridShows() async {
        let (app, _) = ConnectionTests.makeApp(paired: true)
        await app.start()
        var g = app.arrangement
        g = g.placing("mock-room-0", at: Slot(row: 2, half: 3), rows: 3)
        app.saveArrangement(g)
        #expect(app.arrangement.slots["mock-room-0"] == Slot(row: 2, half: 3))
        #expect(app.rooms.last?.id == "mock-room-0")                  // reading order follows
        #expect(app.store.gridArrangement?.slots["mock-room-0"] == Slot(row: 2, half: 3))
    }

    @Test @MainActor func aPlainOrderStillFillsTheGrid() async {
        let (app, _) = ConnectionTests.makeApp(paired: true)
        await app.start()
        app.saveOrder(["mock-room-4", "mock-room-0"])
        #expect(app.rooms.prefix(2).map(\.id) == ["mock-room-4", "mock-room-0"])
        #expect(app.rooms.count == 6)
    }
}
