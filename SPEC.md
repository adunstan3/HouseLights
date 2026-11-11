# House Lights — Spec

Nov 11, 2026 · @Andrew Dunstan

## Overview

House Lights is a watch-only app that controls Philips Hue lights from an Apple Watch Ultra over home Wi-Fi, with no iPhone involved.

- **Device:** Apple Watch Ultra (1st gen), watchOS 26. Watch-only SwiftUI app; the iPhone stays at the office.
- **Hardware:** a Hue Bridge plus bulbs, on a home router with internet.
- **Bundle ID:** com.andrewdunstan.HouseLights. Display name: House Lights.
- **Controls in v1:** rooms and zones (on/off, brightness), color temperature, and a full color wheel. No individual-light control and no scenes in the UI.
- **Extras:** a Smart Stack widget with 2–4 room toggles, and Siri through App Intents.
- **Everything is local:** the app talks only to the bridge on the home network. No Hue account, no cloud, no background location.
- **Mockups:** the House Lights – UI Ideas canvas is the reference for every screen.

## Connection to the Hue Bridge

The watch calls the bridge's local CLIP API v2 over HTTPS on home Wi-Fi; nothing else is contacted.

- **Address:** the user enters the bridge's IP on the Bridge screen. They reserve a fixed IP for it in the router. watchOS can't do mDNS discovery, so there is no auto-discovery.
- **Pairing:** the user presses the bridge's round button, then taps Pair within 30 seconds. The app POSTs to `/api` with `generateclientkey: true` and retries every 2 seconds until the bridge answers or 30 seconds pass. The returned application key (`hue-application-key`) is stored in the Keychain.
- **Certificate:** the bridge uses a self-signed certificate. Trust it with a URLSession delegate that accepts the bridge's certificate only for the saved IP. Never disable certificate checks globally. The certificate seen at pairing is remembered (stored with the key), and a different one is refused later with a "re-pair" message in the log.
- **Local network:** add `NSLocalNetworkUsageDescription` and an App Transport Security exception for local networking (`NSAllowsLocalNetworking`).
- **Reading state:** `GET /clip/v2/resource/room`, `zone`, `grouped_light` and `light`. Rooms and zones come from the bridge, with their names and room types (archetypes).
- **Controlling:** a room or zone is controlled through its `grouped_light` (on, dimming, color\_temperature, color).
- **Live updates:** while the app is open, keep one connection to the event stream `GET /eventstream/clip/v2` (server-sent events) and apply changes as they arrive. Changes made in the Hue app, by a remote or by a switch show up within about a second. Reconnect if the stream drops.
- **Unreachable:** if the bridge doesn't answer (watch not on home Wi-Fi, bridge unplugged), show the Bridge not reachable screen.

## Screens and navigation

Every screen fits one watch screen without scrolling. The one exception is the grid with 10 or more rooms.

| Screen | Reached from | What it holds |
| --- | --- | --- |
| Rooms grid (home) | App launch | Title "House Lights", an all-off button, a gear to Settings, and one tile per room and zone |
| Room | Hold a tile 0.5 s | Back arrow + room name; a top row with the on/off button, brightness % and a brightness bar; a Warmth slider; a Color wheel row; the default-color card |
| Color wheel | Room › Color wheel | Back arrow, Crown brightness readout, and the largest wheel that fits. Nothing else |
| Settings | Grid › gear | Arrange rooms, Bridge |
| Arrange | Settings › Arrange rooms | The same icon grid; dragging reorders it, and nothing here changes lights |
| Bridge (pair) | First launch, or Settings › Bridge | IP field, the press-the-button instruction, Pair; then Paired and Show rooms |
| Bridge not reachable | Any time the bridge doesn't answer | Message, Try again, Bridge settings |

**Rooms grid**

- **Size:** shows every room and zone on the bridge, with none hidden. 1–4 tiles = a 2×2 grid of big tiles; 5–9 = 3×3; 10 or more = three across, scrolled by dragging. Never four across.
- **Tiles:** square, rounded. A lit tile fills with the room's current color, shows a dark icon and its brightness %. An off tile is dark gray and says Off.
- **Icons:** chosen from each room's Hue archetype (sofa for living room, chef's hat for kitchen, bed, monitor for office, door for front door, house for zones, and so on), with a bulb as the fallback. No name labels by default.
- **Tap** a tile to toggle that room. **Hold** it 0.5 s to open its Room screen; a hold never also toggles.
- **All off:** one command to the bridge's all-lights group (`bridge_home`'s `grouped_light`), not one per tile.
- **Order:** the user's order from Arrange. New rooms from the bridge go to the end.

**Arrange drag rules** (to prevent the fighting seen in Closing Time)

1. Hit-test the finger against the grid's fixed slot positions, never against the moving tiles.
2. Change the target slot only when the finger is in the middle 60% of a slot.
3. Wait about 150 ms on a new slot before moving the other tiles, then animate them aside.
4. The dragged tile lifts (slightly larger, white outline) and its order is saved on release.

Arrange tiles look like the grid's current state: lit rooms in their color, off rooms dark gray. They show icons only.

## Behavior details

**Digital Crown on the grid**

- **Rooms that are on:** one Crown step adds the same amount (5 points) to every room that's on, so differences are kept (70% and 40% become 75% and 45%). Rooms that are off are untouched.
- **Rooms only:** the Crown changes rooms, never zones (a zone's bulbs usually belong to a room too). Zones are still shown and toggled by tap. The pill's count is rooms.
- **Limits:** each room stops at 100%. A room that reaches 0% turns off.
- **Back on at 0%:** tapping a room that was dimmed to 0% turns it on at 70%.
- **Feedback:** a small pill ("Brighter · 4 on" or "Dimmer · 4 on") shows briefly while turning.
- **Scrolling:** with 10 or more rooms the Crown still only changes brightness; the grid scrolls by dragging.

**Room screen**

- The Crown sets that room's brightness. Its on/off button toggles the room.
- **Warmth** sets color temperature (2200–6500 K). **Color wheel** sets color. Whichever was touched last is what the lights show.
- The color wheel sends a color when the finger lifts, not on every movement. Convert the wheel's color to Hue's CIE xy coordinates and clamp it to the room's color gamut (the gamut most of its color bulbs share, usually Hue's gamut C), so the swatch matches what the bulbs show. It's sent once through the room's `grouped_light`; the bridge fits it to any bulb with a narrower gamut.

**Temporary colors and defaults**

- Each room has a default color, stored as a bridge scene named "House Lights – \<room name>". Restoring is one scene recall, and the default survives reinstalling the app.
- Any warmth or color change that differs from the default is temporary. It stays through any number of off/on cycles (app, widget, Siri) until the user taps **Back to default**.
- When a room is temporary, the Room screen shows the Temporary color card: the default's swatch and **Back to default** and **Set as default** side by side. Set as default rewrites that room's scene with the current color.
- **Back to default** keeps the room's current brightness. On a room that's off it doesn't turn the lights on; the default comes back the next time the room is turned on.
- If a bulb comes back from a power cut in Hue's own warm white, the color has changed; the app notices through the event stream and drops the temporary label.
- The app remembers which rooms are temporary.

**Bridge rate limits**

- The bridge takes about one `grouped_light` command per second per room. Update tiles and the bar immediately; send each room's latest value at most once a second and drop stale ones in between.
- Crown turns on the grid send per-room commands, throttled the same way.

## Smart Stack widget and Siri

Both run on the same App Intents, so the toggle and brightness logic is written once and shared with the widget extension through an App Group.

**Smart Stack widget**

- Rectangular widget headed "House Lights" with 2–4 round room toggles in the room's color when on and gray when off, each labelled with a short name (a trailing "room" dropped, e.g. "Living").
- The user picks the rooms when adding the widget and changes them by editing it (an AppIntent widget configuration).
- Tapping a toggle runs the toggle intent without opening the app.
- It shows the last-known state; a tap re-checks the bridge and refreshes the widget. It doesn't poll.

**Siri / App Intents**

- Rooms and zones are an `AppEntity`, so Siri knows them by their Hue names.
- Intents: turn a room on, turn it off, set its brightness, set its warmth.
- App Shortcuts phrases: "Turn off the bedroom in House Lights", "Turn on the living room in House Lights", "Set the living room to 30% in House Lights".
- The result shows a small snippet: the room's icon, name and new state (as on the Siri results mockup).
- If the bridge can't be reached, Siri says so plainly.

## Look and app icon

- **Background:** black. Cards and off tiles are dark gray (#1C1C1E); secondary buttons #2C2C2E.
- **Accent:** amber #FFB65C for back arrows, the main buttons and highlights, with dark text (#1A1400) on amber.
- **Lit tiles and swatches** use each room's actual current color.
- **Type:** the system font (SF), bold titles, nothing smaller than the watch's footnote size. Generous tap targets: at least 44 points.
- **App icon:** the refined bulb. A large dark bulb outline (#2A1200), about 68% of the icon's width, centered on solid amber (#FFB65C), with no gradient. The file HouseLights-AppIcon-1024.png goes into Assets › AppIcon; the watch crops it to a circle.

## Data stored on the watch

The bridge is the source of truth for rooms and light state; the watch keeps only what the bridge doesn't.

| What | Where | Notes |
| --- | --- | --- |
| Bridge application key | Keychain, shared access group | Readable by the app and the widget extension |
| Bridge IP | App Group UserDefaults | Shared with the widget |
| Grid order (room ids) | App Group UserDefaults | Unknown new ids are appended |
| Widget room picks | Widget configuration | Set when adding or editing the widget |
| Which rooms are temporary | App Group UserDefaults | Cleared by Back to default or a color change from outside |
| Last-known room states | App Group UserDefaults | For the widget and a fast first paint |
| Room defaults | Bridge scenes "House Lights – \<room>" | Not on the watch |

## Out of scope for v1

- Individual-light control and scenes in the UI.
- Any Hue cloud or remote API, Hue account sign-in, or control away from home Wi-Fi.
- **v2 idea:** turn on the kitchen and living room when arriving home after sunset. It would use the official Hue app registration and the cloud API over cellular, with local Wi-Fi tried first. The first step is testing that the arrival trigger fires reliably on the watch. Apple Home's "People Arrive" automation is the alternative, but needs a home hub. The Automations mockup on the canvas is parked for this.

## Build plan

Eight milestones, each built cleanly in the simulator and committed before the next. The whole app is built first, then uploaded once through TestFlight and tested at home, since the bridge can only be reached on home Wi-Fi.

1. **Bridge layer:** HTTPS client with certificate trust for the saved IP, pairing, the Keychain key, reading rooms, zones and grouped lights, sending commands through a once-a-second-per-room sender, and the event stream. Plus a Bridge log screen recording every request and error, for the first home test.
2. **Bridge and offline screens:** Settings, the Bridge (pair) screen, Bridge not reachable, and first-launch routing.
3. **Rooms grid:** tiles with archetype icons, the 2×2 / 3×3 / scrolling sizes, tap to toggle, hold for the Room screen, all off, live updates from the event stream, and the Crown brightness rules.
4. **Room and Color wheel screens:** brightness, on/off, Warmth, and the wheel with CIE xy conversion and gamut clamping.
5. **Temporary colors and defaults:** the per-room default scenes, the Temporary color card, Back to default and Set as default.
6. **Arrange:** drag-to-reorder with the four drag rules, and the saved order.
7. **Siri and widget:** room entities, App Intents, App Shortcuts phrases, and the Smart Stack widget with room picks.
8. **Polish and final check:** match the Look section and mockups, clear error messages, and a review of the whole app against this spec.
