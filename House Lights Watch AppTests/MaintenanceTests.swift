import AppIntents
import Foundation
import Testing
@testable import House_Lights_Watch_App

/// The Log screen's tools: Remove House Lights scenes and Save bridge replies.
@MainActor
struct MaintenanceTests {
    let red = WheelColor(hue: 0, saturation: 1), blue = WheelColor(hue: 0.66, saturation: 1)

    func ready() async -> (AppModel, MockBridgeClient) {
        let (app, mock) = ConnectionTests.makeApp(paired: true)
        await app.start()
        app.remoteSceneDelay = .milliseconds(100)
        return (app, mock)
    }

    @Test func removeScenesDeletesEveryHouseLightsScene() async {
        let (app, mock) = await ready()
        app.setRemoteScene("mock-room-0", enabled: true)
        app.setHybrid([red, blue], moving: true, roomID: "mock-room-0")
        app.setWarmth(kelvin: 4000, roomID: "mock-room-3")                  // creates Office's default
        #expect(await eventually {
            let home = await mock.currentHome
            return home.remoteScenes["mock-room-0"] != nil && home.mixScenes["mock-room-0"] != nil && home.defaults["mock-room-3"] != nil
        })
        #expect(app.ownSceneCount >= 3)
        await app.removeAllScenes()
        let home = await mock.currentHome
        #expect(home.defaults.isEmpty && home.remoteScenes.isEmpty && home.mixScenes.isEmpty)
        #expect(app.ownSceneCount == 0)
        #expect(app.remoteRooms.isEmpty && app.hybrids.isEmpty && app.temporaryRooms.isEmpty)
        #expect(app.store.remoteRooms.isEmpty)
        #expect(app.room("mock-room-0")?.isOn == true)                        // the lights stay as they are
    }

    @Test func bridgeRepliesAreSavedAsOneJSONFile() async throws {
        let (app, _) = await ready()
        app.bridgeRepliesURL = FileManager.default.temporaryDirectory.appending(path: "replies-\(UUID()).json")
        let url = try #require(await app.saveBridgeReplies())
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        #expect(Set(object?.keys.map { $0 } ?? []) == Set(AppModel.replyResources))
    }

    @Test func bridgeRepliesAreDeletedAfterAWeek() async throws {
        let (app, _) = await ready()
        app.bridgeRepliesURL = FileManager.default.temporaryDirectory.appending(path: "replies-\(UUID()).json")
        let url = try #require(await app.saveBridgeReplies())
        #expect(!app.removeStaleBridgeReplies(now: .now.addingTimeInterval(6 * 24 * 3600)))   // 6 days: kept
        #expect(FileManager.default.fileExists(atPath: url.path()))
        #expect(app.removeStaleBridgeReplies(now: .now.addingTimeInterval(8 * 24 * 3600)))    // 8 days: gone
        #expect(!FileManager.default.fileExists(atPath: url.path()))
    }

    @Test func roomIntentsNeedAnUnlockedWatch() {
        #expect(TurnOnRoomIntent.authenticationPolicy == .requiresAuthentication)
        #expect(TurnOffRoomIntent.authenticationPolicy == .requiresAuthentication)
        #expect(SetRoomBrightnessIntent.authenticationPolicy == .requiresAuthentication)
        #expect(SetRoomWarmthIntent.authenticationPolicy == .requiresAuthentication)
        #expect(ToggleRoomIntent.authenticationPolicy == .requiresAuthentication)
    }

    @Test func logTextHasEveryEntry() async {
        let (app, _) = await ready()
        app.log.add(.error, "Something went wrong")
        #expect(app.logText.contains("Something went wrong"))
        #expect(app.logText.split(separator: "\n").count == app.log.entries.count)
    }
}
