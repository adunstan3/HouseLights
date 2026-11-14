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
- **Certificate:** the bridge uses a self-signed certificate. Trust it with a URLSession delegate that accepts the bridge's certificate only for the saved IP. Never disable certificate checks globally. The certificate seen at pairing is remembered (its SHA-256 hash, stored with the key), and a different one is refused later with a "re-pair" message in the log. Accepting whatever certificate the bridge presents happens only while pairing; every other connection (app, widget, Siri) must have the pin. A saved key without a pin counts as needing re-pairing: nothing is sent, the app shows Bridge not reachable with the re-pair message, and Siri says to pair again. Pairing saves the key and the pin together or not at all: if no certificate was seen or either Keychain save fails, pairing fails with a message and keeps nothing.
- **Local network:** add `NSLocalNetworkUsageDescription` and an App Transport Security exception for local networking (`NSAllowsLocalNetworking`).
- **Reading state:** `GET /clip/v2/resource/room`, `zone`, `grouped_light` and `light`. Rooms and zones come from the bridge, with their names and room types (archetypes).
- **Controlling:** a room or zone is controlled through its `grouped_light` (on, dimming, color\_temperature, color).
- **Live updates:** while the app is open, keep one connection to the event stream `GET /eventstream/clip/v2` (server-sent events) and apply changes as they arrive. Changes made in the Hue app, by a remote or by a switch show up within about a second. Reconnect if the stream drops.
- **Unreachable:** if the bridge doesn't answer (watch not on home Wi-Fi, bridge unplugged), show the Bridge not reachable screen.

## Screens and navigation

Every screen fits one watch screen without scrolling. The one exception is the grid with 10 or more rooms.

| Screen | Reached from | What it holds |
| --- | --- | --- |
| Rooms grid (home) | App launch | All-off button left of the clock, a gear to Settings right of it, the title "Lights" centered under the time, and one tile per room |
| Room | Hold a tile 0.5 s | Back arrow + room name; a top row with the on/off button, brightness % and a brightness bar; a Warmth slider; a Color wheel row; the default-color card |
| Color wheel | Room › Color wheel | Back button and a pin button either side of the clock, the largest wheel that fits, and saved colors below it. Brightness is set on the Room screen; the Crown scrolls here |
| Settings | Grid › gear | Arrange rooms, Remote scenes, Bridge. Back from Settings, Arrange or Bridge goes straight to the grid |
| Arrange | Settings › Arrange rooms | The same icon grid with every empty spot outlined; drag a room to any spot, and nothing here changes lights |
| Bridge (pair) | First launch, or Settings › Bridge | IP field, the press-the-button instruction, Pair; then Paired and Show rooms |
| Bridge not reachable | Any time the bridge doesn't answer | Message, Try again, Bridge settings |

**Rooms grid**

- **Size:** shows every room on the bridge, with none hidden. Zones are not shown on the grid or in Arrange (they're still available to Siri and the widget). 1–4 tiles = two across (big tiles); 5–9 = three across; 10 or more = three across, scrolled by dragging. Never four across. Tiles are as large as the rows in use allow, so 5–6 rooms fill the screen's width.
- **Tiles:** square, rounded. A lit tile fills with the room's current color, shows a dark icon and its brightness %. An off tile is dark gray and says Off.
- **Icons:** chosen from each room's Hue archetype (sofa for living room, frying pan for kitchen (SF Symbols has no chef's hat), bed, monitor for office, door for front door, house for zones, and so on), with a bulb as the fallback. No name labels by default.
- **Live updates backup:** while the app is open it also reads the lights' state (quietly, logging only failures), so remotes, switches and the Hue app show up even if the event stream isn't delivering: every 3 seconds while the stream is down or hasn't delivered anything, every 20 seconds while it is delivering updates (it drops back to 3 seconds as soon as the stream drops). The log notes the first update each event-stream connection receives.
- **Live updates while tapping:** for two seconds after the app changes a room, its own state wins over live updates for that room (the bridge can echo older or in-between states); the newest update is applied once that time is up.
- **Tap** a tile to toggle that room. **Hold** it 0.5 s to open its Room screen; a hold never also toggles.
- **All off:** one command to the bridge's all-lights group (`bridge_home`'s `grouped_light`), not one per tile.
- **Placement:** rooms sit where Arrange put them: any spot on the grid, including half-way between two columns, with gaps kept (nothing packs towards the top left). Until arranged, rooms fill the grid in order. New rooms from the bridge go to the first free spot.

**Arrange drag rules** (to prevent the fighting seen in Closing Time)

1. Hit-test the finger against the grid's fixed slot positions, never against the moving tiles. Slots are half a tile apart across (three-across rows have five: the three columns and the two half-way spots) and a row apart down.
2. Change the target slot only when the finger is in the middle 60% of a slot's cell.
3. Wait about 150 ms on a new slot before moving the other tiles, then animate them aside: a room in the way slides to the nearest free spot (two rooms, for a half-way drop). The others are always placed from where they were when the drag began, so a room passed over goes back.
4. The dragged tile lifts (slightly larger, white outline) and the arrangement is saved on release.

Arrange uses the rows that fit the screen (two for one to four rooms, three otherwise), adding a row only when nothing else is free.

Once a slot is the target, it stays the target while the finger is anywhere on that slot, so a held tile always makes room after ~150 ms. With more than nine rooms the Arrange tiles shrink so it never scrolls.

Arrange tiles look like the grid's current state: lit rooms in their color, off rooms dark gray. They show icons only.

## Behavior details

**Digital Crown on the grid**

- **Rooms that are on:** one Crown step adds the same amount (5 points) to every room that's on, so differences are kept (70% and 40% become 75% and 45%). Rooms that are off are untouched.
- **Rooms only:** the Crown changes rooms, never zones.
- **Limits:** each room stops at 100%. A room that reaches 0% turns off.
- **Back on at 0%:** tapping a room that was dimmed to 0% (Crown or slider) turns it on at 70%. A room switched off any other way (tap, all off, a remote) comes back at its own last brightness, and an off room keeps showing that level even though the bridge reports 0 for it.
- **Feedback:** a small pill ("Brighter · 4 on" or "Dimmer · 4 on") shows briefly over the top of the grid while turning. The Crown's scroll indicator is hidden.
- **Scrolling:** with 10 or more rooms the Crown still only changes brightness; the grid scrolls by dragging.

**Room screen**

- The Crown sets that room's brightness in 5% steps (snapping to multiples of 5), with no scroll indicator; the brightness bar is also a slider you can drag. Its on/off button toggles the room.
- Changing warmth or color of a room that's off doesn't turn it on: the change is sent without "on" (current Hue bulbs apply it when next switched on), and the tile stays off.
- **Warmth** sets color temperature (2200–6500 K). **Color wheel** sets color. Whichever was touched last is what the lights show.
- **Hybrids:** tapping saved colors selects them (numbered in the order tapped, up to 9). One selected is a single color; two or more make a hybrid: each color bulb gets one of the colors, in turn. A **Moving** toggle appears for a hybrid; it's forced on when there are more colors than color bulbs. Moving hybrids are played by the bridge as a Hue dynamic scene (the lights morph between the colors), so they keep going after the watch is put away. While Moving is on, **Slow / Medium / Fast** buttons set the bridge's speed (0.25 / 0.5 / 0.8; Slow for hybrids saved before speeds existed); the speed is written into the scene, since a recall can't set it. Dragging on the wheel goes back to a single color. A hybrid is shown through a working scene per room, "House Lights Mix – \<room\>" (per-light colors, the palette, and `auto_dynamic` when moving). On a room that's off, the hybrid is saved and shown the next time the app turns it on.
- **Hybrid tiles:** a room whose lights show different colors has its tile (and power button, widget toggle) filled with a diagonal blend of them. A lit, moving hybrid's grid tile, Room-screen power button and Set as default button slowly drift through its colors (Back to default too, when the default is a moving hybrid) (a gradient turning once every 14 seconds; still with Reduce Motion). The Room screen's warmth label reads "Mix" or "Mix · moving" (no knob until dragged).
- **Hybrids and off rooms:** switching a room off (in the app, by a remote) keeps its hybrid; Siri and the widget turn on a hybrid that's waiting for turn-on.
- **Hybrid defaults:** Set as default saves a hybrid as the room's default (per-light colors, palette, and whether it moves); Back to default brings it back, moving if it was. Remote scenes follow hybrids too, and start moving ones moving. While the bulbs morph (or still show the hybrid's colors) the room stays temporary.
- **Saved colors:** the pin button saves the wheel's current color. Saved colors sit below the wheel as swatches, four across, newest first; turn the Crown or drag the page to scroll to them (dragging on the wheel picks a color). Tap swatches to select them (see Hybrids); hold one to remove it. They're shared by every room and kept on the watch; near-duplicates aren't saved twice.
- The color wheel sends a color when the finger lifts, not on every movement. Convert the wheel's color to Hue's CIE xy coordinates and clamp it to the room's color gamut (the gamut most of its color bulbs share, usually Hue's gamut C), so the swatch matches what the bulbs show. It's sent once through the room's `grouped_light`; the bridge fits it to any bulb with a narrower gamut.

**Temporary colors and defaults**

- Each room has a default color, stored as a bridge scene named "House Lights – \<room name>". Restoring is one scene recall, and the default survives reinstalling the app.
- Any warmth or color change that differs from the default is temporary. It stays through any number of off/on cycles (app, widget, Siri) until the user taps **Back to default**.
- When a room is temporary, the Room screen shows two tall buttons side by side: **Back to default**, filled with the room's default color, and **Set as default**, filled with the lights' current color (labels wrap onto two lines; white text on dark colors). Set as default rewrites that room's scene with the current color.
- **Back to default** keeps the room's current brightness. On a room that's off it doesn't turn the lights on; the default comes back the next time the room is turned on.
- If a bulb comes back from a power cut in Hue's own warm white, the color has changed; the app notices through the event stream and drops the temporary label.
- The app remembers which rooms are temporary.

**Errors**

- No answer from the bridge (or a changed certificate or rejected key) shows Bridge not reachable. A change the bridge refuses shows a short notice for three seconds. Every request and error is in Settings › Bridge › Log. The Log screen also has: a share button (the log as text); **Save bridge replies** (the raw `room`, `zone`, `grouped_light`, `light`, `scene`, `device` and `bridge_home` lists saved as one JSON file, then shareable); and **Remove House Lights scenes** (after a confirmation, deletes every "House Lights…" scene on the bridge, including leftovers from renamed rooms, and forgets defaults, hybrids and remote rooms; lights are left as they are).

**Remote scenes (Hue dimmer switches)**

- Settings › Remote scenes shows the rooms as tiles; tap the rooms that have a dimmer switch. Each gets a bridge scene **"House Lights Now – \<room\>"**, created from the room's current look.
- After every color, warmth or brightness change the watch makes in that room, the scene is rewritten with the new look, about 1.5 s after the room is left alone (one request; the lights themselves change first, as always). Back to default copies the default into it.
- Turning a room off with a tap or All off never changes the scene: it always means "on", at 1% or more. Dimming a room to 0% with the Crown or slider saves it at 70%, so the remote brings it back at 70% (as a tap in the app does).
- In the Hue app, set each dimmer's On button to its room's "House Lights Now" scene; the remote then turns the room on in whatever the watch last set. The real default stays in "House Lights – \<room\>".
- Changes made with the Hue app or the remote's dim buttons don't update the scene.
- Turning a room's tile off on this screen stops updating its scene but leaves the scene on the bridge (a remote may still use it).

**Bridge rate limits**

- The bridge takes about one `grouped_light` command per second per room. Update tiles and the bar immediately; send each room's latest value at most once a second and drop stale ones in between.
- Crown turns on the grid send per-room commands, throttled the same way.

## Smart Stack widget and Siri

Both run on the same App Intents, so the toggle and brightness logic is written once and shared with the widget extension through an App Group.

**Smart Stack widget**

- Rectangular widget headed "House Lights" with 2–4 round room toggles in the room's color when on and gray when off, each labelled with a short name (a trailing "room" dropped, e.g. "Living").
- The user picks the rooms when adding the widget and changes them by editing it (an AppIntent widget configuration).
- Tapping a toggle runs the toggle intent without opening the app.
- It shows the last-known state; a tap re-checks the bridge and refreshes the widget. It doesn't poll. Changes made in the app (or arriving from the bridge while the app is open) reload the widget about 2 seconds after they stop.

**Siri / App Intents**

- Rooms and zones are an `AppEntity`, so Siri knows them by their Hue names.
- Intents: turn a room on, turn it off, set its brightness, set its warmth.
- App Shortcuts phrases: "Turn off the bedroom in House Lights", "Turn on the living room in House Lights", "Set the living room in House Lights" (Siri then asks for the percentage: a phrase can hold only one parameter, the room). "Set the living room warmth in House Lights" asks for the kelvin.
- The result shows a small snippet: the room's icon, name and new state (as on the Siri results mockup).
- Siri and the widget follow the app's rules: a pending default or hybrid is shown on turn-on, 0% → 70%, a warmth replaces a hybrid, and a room with a remote scene has its "House Lights Now" scene updated (brightness kept with its colors; a warmth replaces them).
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
| Bridge application key, certificate pin (SHA-256) | Keychain, shared access group | Readable by the app and the widget extension; saved together or not at all |
| Bridge IP | App Group UserDefaults | Shared with the widget |
| Grid order (room ids) | App Group UserDefaults | Unknown new ids are appended |
| Widget room picks | Widget configuration | Set when adding or editing the widget |
| Which rooms are temporary | App Group UserDefaults | Cleared by Back to default or a color change from outside |
| Last-known room states | App Group UserDefaults | For the widget and a fast first paint |
| Room defaults | Bridge scenes "House Lights – \<room>" | Not on the watch |
| Saved colors, hybrids (colors, moving, speed), remote rooms | App Group UserDefaults | Hybrids saved without a speed load as Slow |
| Saved bridge replies | App Group folder, bridge-replies.json | Only when Save bridge replies is tapped |

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
