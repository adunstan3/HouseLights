# House Lights — checks for the first test at home

The simulator uses a mock bridge, so everything below can only be confirmed on the watch,
on home Wi-Fi. If something fails, open **Settings › Bridge › Log ›** and take a photo; every
request, response code and error is there (newest first).

## Before uploading (Mac)

1. **Bundle IDs.** On developer.apple.com › Identifiers, register (or let Xcode register):
   - `com.andrewdunstan.HouseLights` (container, used for the App Store Connect record)
   - `com.andrewdunstan.HouseLights.watchkitapp` (watch app)
   - `com.andrewdunstan.HouseLights.watchkitapp.widget` (Smart Stack widget)
2. **App Group.** Identifiers › App Groups › + › `group.com.andrewdunstan.HouseLights`. Enable
   *App Groups* on the watch app and widget IDs and tick that group.
3. **In Xcode,** open Signing & Capabilities for *House Lights Watch App* and *House Lights Widget*:
   both should list App Groups (the group above) and Keychain Sharing
   (`com.andrewdunstan.HouseLights.shared`), team **Andrew Dunstan**. If either shows a red
   error, press "Try Again" or untick/retick "Automatically manage signing".
4. Bump the build number on all targets, archive with **Any watchOS Device**, upload.

## At home

| Check | What should happen | If not, look in the log for |
| --- | --- | --- |
| Local network | The watch may ask to allow local network access: allow it. | `secure connection failed`, `no answer at …` |
| Pairing | Enter the bridge IP, press its button, tap Pair within 30 s → "Paired, N rooms and M zones". | `POST /api` replies; error 101 means the button wasn't pressed |
| Certificate | Pairing remembers the bridge's certificate. A later "certificate changed" means the bridge was replaced/reset: Pair again. | `Certificate changed` |
| Grid | Every room and zone appears with a sensible icon; tap toggles; hold opens the room without toggling. | `PUT /clip/v2/resource/grouped_light/…` and its code |
| Live updates | Change a light in the Hue app or at a switch: the tile updates within a second or two. Status stays connected while the app is open. | `GET /eventstream/clip/v2`, `Event stream dropped; reconnecting` |
| Crown on grid | Rooms that are on brighten/dim together; 100% stops; 0% turns off; tap brings it back at 70%. Tune the Crown speed if it feels too fast or slow. | |
| Room screen | Crown brightness, power, Warmth and the color wheel all change the lights while you use them (at most once a second). | `Bridge says: …` after a grouped_light PUT |
| Temporary colors | Change warmth → Back to default appears; it survives off/on; Back to default restores it; Set as default sticks. "House Lights – <room>" scenes appear in the Hue app. | `POST /clip/v2/resource/scene`, `recall` |
| Arrange | Dragging is smooth, a held tile makes room, the order sticks after closing the app. | |
| Widget | Add it to the Smart Stack, pick rooms (edit the widget), toggle without opening the app. | `Intent: toggle …` |
| Siri | "Turn off the bedroom in House Lights"; "Set the living room in House Lights" (Siri asks for the %). | `Intent: …` |
| Off Wi-Fi | Walk out of range: Bridge not reachable appears instead of hanging. | `timed out` |

## Hue API details I couldn't confirm without a bridge

- **Color through `grouped_light`.** Forum reports disagree on whether a room's grouped_light
  accepts `color` and `color_temperature` on every bridge firmware. If the Warmth slider or the
  wheel does nothing, the log will show the bridge's error for that PUT; the fix would be to
  send color per light (within the rate limit).
- **Scene recall with brightness.** Back to default sends `recall: { action: "active",
  dimming: { brightness } }` to keep the room's brightness. Confirm the brightness stays put.
- **Scene names** are kept within 32 characters (the limit a third-party Hue connector
  documents). Long room names are shortened in the scene name.
- **Event stream on watchOS.** watchOS may close long-lived connections when the wrist drops;
  the app reconnects when it becomes active again and reloads to catch up.
- **Bulbs that are off ignore color changes**, so Back to default on an off room is applied
  the next time House Lights turns it on (app, widget or Siri), as agreed.
