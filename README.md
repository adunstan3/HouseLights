<p align="center">
  <img src="docs/icon.png" width="120" alt="House Lights icon: a dark bulb outline on amber">
</p>

<h1 align="center">House Lights</h1>

<p align="center">
  An Apple Watch app that controls Philips Hue lights straight from the wrist,<br>
  over home Wi-Fi, with no iPhone, Hue account or cloud involved.
</p>

---

House Lights is a standalone app for the Apple Watch Ultra. It talks to the Hue Bridge's
local **CLIP API v2** over HTTPS on the home network, so it works with the iPhone left at
the office. Every room is a tile: tap to switch it, hold to open it, and turn the Digital
Crown to brighten or dim everything that's on. A Smart Stack widget and Siri use the same
logic.

It's a personal project, installed through TestFlight.

**Version 1.0 (build 4)** · watchOS 26 · SwiftUI, App Intents and WidgetKit · no third-party packages

## Contents

- [How it works](#how-it-works)
  - [Rooms grid](#rooms-grid)
  - [Room screen](#room-screen)
  - [Color wheel](#color-wheel)
  - [Defaults and temporary colors](#defaults-and-temporary-colors)
  - [Remote scenes](#remote-scenes)
  - [Arrange](#arrange)
  - [Pairing with the bridge](#pairing-with-the-bridge)
  - [Bridge not reachable](#bridge-not-reachable)
  - [Bridge log](#bridge-log)
  - [Smart Stack widget](#smart-stack-widget)
  - [Siri](#siri)
- [How it talks to the bridge](#how-it-talks-to-the-bridge)
- [Scenes House Lights keeps on the bridge](#scenes-house-lights-keeps-on-the-bridge)
- [What's stored on the watch](#whats-stored-on-the-watch)
- [Building and running](#building-and-running)
- [Tests](#tests)
- [Project layout](#project-layout)
- [Known limits](#known-limits)

## How it works

### Rooms grid

The app opens on a grid with one tile per Hue room. A lit tile is filled with the room's
real color and shows its brightness; an off tile is dark gray and says **Off**. Icons come
from each room's Hue type (sofa, frying pan, bed, monitor, door…), with a bulb as the
fallback. Zones aren't shown.

<p>
  <img src="docs/screenshots/grid.png" width="180" alt="Rooms grid with six rooms">
  <img src="docs/screenshots/grid-4.png" width="180" alt="Rooms grid with four big tiles">
  <img src="docs/screenshots/grid-12.png" width="180" alt="Rooms grid with twelve rooms, scrolling">
</p>

- **Tap** a tile to switch the room on or off. **Hold** it for half a second to open the
  room; a hold never also switches it.
- **Sizes:** 1–4 rooms are big tiles two across; 5–9 are three across; 10 or more are three
  across and scroll by dragging. Never four across.
- **Digital Crown:** each click adds or removes 5% on every room that's on, so their
  differences are kept (70% and 40% become 75% and 45%). Rooms stop at 100%; a room
  dimmed to 0% turns off, and a tap brings it back at 70%. A pill shows
  "Brighter · 4 on" while you turn. With 10+ rooms the Crown still only changes
  brightness.
- **All off** (left of the clock) turns every light off with one command; the gear (right
  of the clock) opens Settings.
- **Live:** changes made in the Hue app, with a switch or a remote show up within a second
  through the bridge's event stream. A quiet backup read runs every 3 seconds while the
  stream is silent or down, and every 20 seconds while the stream is delivering updates.

### Room screen

<p>
  <img src="docs/screenshots/room.png" width="180" alt="Room screen with Back to default and Set as default">
  <img src="docs/screenshots/room-office.png" width="180" alt="Room screen for a room showing a color">
</p>

The power button switches the room. Drag the brightness bar, or turn the Crown in 5% steps;
**Warmth** slides from 2200 K to 6500 K. Changes reach the lights while you turn or drag (at
most once a second per room, which is what the bridge allows). Changing the color of a room
that's off doesn't turn it on; the new color shows when it's next switched on.

### Color wheel

<p>
  <img src="docs/screenshots/color-wheel.png" width="180" alt="Color wheel">
  <img src="docs/screenshots/swatches.png" width="180" alt="Saved colors below the wheel">
</p>

The largest wheel that fits; brightness is set on the Room screen, so here the Crown
scrolls. The color is sent when your finger lifts, converted to Hue's CIE xy
coordinates and fitted to the colors the room's bulbs can show.

<p>
  <img src="docs/screenshots/hybrid-colors.png" width="180" alt="Two saved colors selected as a moving hybrid, with Slow, Medium and Fast">
  <img src="docs/screenshots/hybrid-grid.png" width="180" alt="A moving hybrid room's tile with its colors drifting">
  <img src="docs/screenshots/room-hybrid.png" width="180" alt="Room screen for a moving hybrid: Mix · moving">
</p>

**Hybrids:** tap two or more saved colors and each bulb in the room gets one of them. Turn
on **Moving** and the bridge slowly morphs the lights between the colors (a Hue dynamic
scene, so it keeps going after you put the watch away); it's forced on when you pick more
colors than the room has bulbs. While Moving is on, **Slow / Medium / Fast** sets how quickly
the bridge morphs (0.25, 0.5 and 0.8 on the bridge's 0–1 scale). The room's tile blends the
colors; a moving hybrid's tile, Room-screen power button and Set as default button (and
Back to default, when the default is a moving hybrid) slowly drift through them
(still, with Reduce Motion on). The Room screen's warmth label reads **Mix** or
**Mix · moving**. A hybrid picked for a room that's off waits for the next turn-on, from the
app, the widget or Siri. Set as default saves a hybrid as the room's default, moving and
speed included, and remote scenes start it too.

The **pin** button right of the clock saves the current color. Saved colors appear below
the wheel, four across; turn the Crown or drag the page to scroll to them. Tap a swatch to use it in this
room (or several, for a hybrid), hold it to remove it. They're shared by every room.

### Defaults and temporary colors

Each room's default color is saved on the bridge as a scene called
**"House Lights – \<room\>"**, created from the room's current look the first time you
change its warmth or color, so it survives reinstalling the app. Any other color is
*temporary*: it stays through any number of off/on cycles, and the Room screen shows two
buttons: **Back to default** (filled with the default color) and **Set as default**
(filled with the current color). Back to default keeps the room's brightness; on a room
that's off, the default comes back the next time House Lights turns it on. A color changed
outside the app (the Hue app, a switch, a power cut) drops the temporary label.

### Remote scenes

<p>
  <img src="docs/screenshots/remote-scenes.png" width="180" alt="Remote scenes: choose rooms with a dimmer switch">
</p>

For rooms with a Hue dimmer switch: Settings › Remote scenes, tap the rooms. Each gets a
scene **"House Lights Now – \<room\>"** that the watch rewrites (about 1.5 seconds after you
stop adjusting) with every color, warmth or brightness change it makes. Set the dimmer's On
button to that scene in the Hue app and the remote turns the room on in whatever the watch
last chose. Turning a room off never saves "off" into it; a room dimmed to 0% comes back at
70% from the remote, as it does from the app. Back to default resets the scene too.

### Arrange

<p>
  <img src="docs/screenshots/settings.png" width="180" alt="Settings">
  <img src="docs/screenshots/arrange.png" width="180" alt="Arrange with empty spots outlined">
  <img src="docs/screenshots/grid-free.png" width="180" alt="Grid with rooms spread out and half-way spots">
</p>

Settings › Arrange rooms shows the same grid in its current state, with every empty spot
outlined. Drag a room to **any spot** — including half-way between two columns — and the
grid keeps it there, gaps and all. A room in the way slides to the nearest free spot.
Nothing here changes the lights. The drag follows four rules so tiles never fight: the
finger is checked against fixed slot positions (never the moving tiles), a spot only
becomes the target from its middle 60%, the others move aside after about 150 ms on a new
spot (and go back if you move on), and the layout is saved on release. New rooms from the
bridge go to the first free spot. Back from Settings or Arrange goes straight to the grid.

### Pairing with the bridge

<p>
  <img src="docs/screenshots/pair.png" width="180" alt="Bridge screen before pairing">
  <img src="docs/screenshots/bridge.png" width="180" alt="Bridge screen after pairing">
</p>

On first launch (and from Settings › Bridge): enter the bridge's IP address (reserve it in
your router — watchOS can't discover the bridge), press the round button on the bridge,
then tap **Pair** within 30 seconds. The app asks every 2 seconds until the bridge
answers, then shows how many rooms and zones it found.

### Bridge not reachable

<p>
  <img src="docs/screenshots/unreachable.png" width="180" alt="Bridge not reachable">
</p>

Shown whenever the bridge doesn't answer (watch not on home Wi-Fi, bridge unplugged), with
**Try again** and **Bridge settings**. A change the bridge refuses shows a short notice
instead.

### Bridge log

<p>
  <img src="docs/screenshots/log.png" width="180" alt="Bridge log">
</p>

Settings › Bridge › Log › records every request, response code and error, newest first,
and survives relaunches — so a photo of it explains any problem at home. The share button
by the clock sends the whole log as text (Messages or Mail). At the bottom of the log:

- **Save bridge replies** reads the bridge's `room`, `zone`, `grouped_light`, `light`,
  `scene`, `device` and `bridge_home` lists exactly as sent and saves them as one JSON file
  (`bridge-replies.json` in the App Group folder), then offers **Share bridge replies**. The
  replies hold no key or password.
- **Remove House Lights scenes** (after a confirmation) deletes every "House Lights…" scene
  on the bridge (defaults, "Now" and "Mix" scenes, including leftovers from renamed rooms)
  and forgets the defaults, hybrids and remote rooms. The lights stay as they are; a dimmer
  pointed at a "Now" scene stops working until you set it up again.
- **Clear log.**

### Smart Stack widget

<p>
  <img src="docs/screenshots/widget.png" width="280" alt="Smart Stack widget with three room toggles">
</p>

A rectangular widget with up to four round toggles in each room's color. Choose the rooms
by editing the widget on the watch. A tap switches the room without opening the app, then
the widget shows the bridge's new state; it doesn't poll. Changes made in the app reach the
widget about 2 seconds after they stop.

### Siri

<p>
  <img src="docs/screenshots/siri.png" width="280" alt="Siri results for turning a room off and setting brightness">
</p>

Rooms (and zones) are known to Siri by their Hue names:

- "Turn off the bedroom in House Lights" / "Turn on the living room in House Lights"
- "Set the living room in House Lights" — Siri then asks for the percentage
- "Set the living room warmth in House Lights" — Siri then asks for the kelvin

Siri and the widget follow the app's rules: a default or hybrid waiting for turn-on is
shown, a room dimmed to 0% comes back at 70%, a warmth replaces a hybrid, and a room with a
remote scene has its "Now" scene updated too. If the bridge can't be reached, Siri says so
plainly.

## How it talks to the bridge

- **HTTPS with the bridge's own certificate.** Hue bridges use a certificate iOS doesn't
  trust, so a URLSession delegate accepts it only for the saved bridge IP, remembers the
  certificate seen at pairing, and refuses a different one later. Checks are never
  relaxed for anything else.
- **Pairing:** `POST /api` with `generateclientkey`; the application key goes in the
  Keychain.
- **Reading:** `room`, `zone`, `grouped_light`, `light` and `scene` resources.
- **Controlling:** rooms are switched through their `grouped_light`; "all off" uses the
  bridge's all-lights group. A per-room sender sends at most one command a second and only
  the latest value.
- **Live updates:** one `/eventstream/clip/v2` connection while the app is open,
  reconnecting if it drops. For two seconds after the app changes a room, the app's own
  state wins over the stream (the bridge echoes older and in-between states).
- **Nothing else:** no Hue account, cloud, analytics or location.

## Scenes House Lights keeps on the bridge

Each room can have up to three scenes from House Lights (they show in the Hue app's scene list):

| Scene | What it's for | Created when |
| --- | --- | --- |
| **House Lights – \<room\>** | The room's default (Back to default, Set as default) | The first time you change the room's color or warmth, or tap Set as default |
| **House Lights Now – \<room\>** | What a dimmer switch's On button recalls; rewritten with every change the watch makes | When you pick the room in Settings › Remote scenes |
| **House Lights Mix – \<room\>** | The app's working scene for showing a hybrid | The first time you pick a hybrid in that room |

Point remotes at the "Now" scenes, never the "Mix" ones; a hybrid is copied into the room's
"Now" scene too, so the remote brings it back. Scenes you made yourself are never touched.
Settings › Bridge › Log › **Remove House Lights scenes** deletes all of them at once.

## What's stored on the watch

| What | Where |
| --- | --- |
| Bridge application key, pinned certificate hash | Keychain, shared with the widget |
| Bridge IP, grid order, temporary rooms, last-known room states | App Group defaults, shared with the widget |
| Room defaults | Scenes on the bridge, "House Lights – \<room\>" |
| Saved colors, hybrids (colors, moving, speed), remote rooms, grid layout | App Group defaults |
| Bridge log | App Group folder (`bridge-log.json`) |
| Saved bridge replies (only when you tap Save) | App Group folder (`bridge-replies.json`) |

## Building and running

Open `House Lights.xcodeproj` in Xcode 27 and run the **House Lights Watch App** scheme.
The simulator can't reach a Hue bridge, so it uses a **mock bridge** with six sample rooms
and a zone. Scripts use their own "House Lights Tests" simulator so they never disturb
the one you run from Xcode:

- `scripts/run.sh [shot.png] [launch args…]` builds, installs, launches and optionally
  screenshots.
- `scripts/shots.sh <dir> name "args" …` screenshots several states in one go.
- `scripts/test.sh` and `scripts/uitest.sh` run the unit and UI tests.
- `scripts/open.sh [--no-launch] [launch args…]` builds and opens the app on your own simulator (the one in DeviceHub); `--no-launch` only installs it.
- `scripts/locked.sh command…` runs any other build or simulator command under the shared lock.

Every script waits for a lock shared with my other watch apps (`~/Library/Caches/watchapps-build.lock`, see `scripts/lock.sh`), so only one build or test
runs on the Mac at a time. A script that prints "Waiting for the shared build lock" is queued, not stuck.

Debug launch arguments (simulator / debug builds):
`-mockTiles 12`, `-unpaired YES`, `-mockOffline YES`, `-mockTemporary YES`,
`-mockOutsideChanges YES`, `-mockSwatches YES`, `-scrollSwatches YES`, `-mockFreeLayout YES`, `-mockHybrid YES`,
`-realBridge YES`, `-openScreen settings|bridge|log|arrange|room|wheel`,
`-openRoom "Office"` (`-openScreen remotes` opens Remote scenes).

### Releasing through TestFlight

Commit everything, then run `scripts/release.sh` (the same script in all three watch apps;
this app's values are in `scripts/app.env`). It refuses uncommitted changes; picks the
build number (each uploaded build is tagged `build-<N>`, and if the current number is
already tagged it bumps every target and commits "Build N"); runs the unit tests
(`UI_TESTS=1` adds the UI tests); archives for any watchOS device; checks the build number
and `ITSAppUsesNonExemptEncryption = NO` in the archive; uploads to App Store Connect for
internal TestFlight testing with the Apple ID signed in to Xcode; and tags the commit
`build-<N>`. `PUSH=1` also pushes the branch and the tag. Logs: `build/archive.log`,
`build/export.log`.

## Tests

- **143 unit tests** (Swift Testing, about 5 seconds): color maths and gamut clamping,
  command merging and the once-a-second sender, the event-stream parser, building the home
  from bridge-shaped JSON, pairing and certificate pinning, grid sizes, the Crown rules,
  the four Arrange drag rules, defaults and temporary colors, live sending while dragging,
  the settle window and reloads racing a tap, saved colors, hybrids (off rooms, speed,
  drifting colors), remote scenes, Siri actions (waiting hybrids, remote scenes) and the
  widget's rooms, and the Log tools (removing scenes, saving replies). Tests wait for
  results with `eventually { … }` rather than fixed sleeps. Widget and Siri snapshots render
  to PNGs with `TEST_RUNNER_SNAPSHOT_DIR=… scripts/test.sh`.
- **12 UI tests** (XCTest, about 2 minutes): tap toggles, hold opens without toggling, the
  Crown on every screen (and never scrolling the big grid), a real Arrange drag, the
  temporary buttons appearing at once, pinning, scrolling to and removing a saved color, and
  Back going straight to the grid.

## Project layout

```
House Lights Watch App/   the app: Screens/ (Grid, Room, ColorWheel, Settings, Arrange,
                          Bridge, Shared), Model/ (AppModel and its extensions, Router,
                          layout and drag maths), Intents/ (Siri phrases), Support/
House Lights Widget/      the Smart Stack widget extension
Shared/                   built into both: Bridge/ (client, trust, sender, event stream,
                          log, mock), Models/, Storage/ (Keychain, App Group), Intents/,
                          Widget/ (the widget's view and configuration)
House Lights Watch AppTests/, House Lights Watch AppUITests/
Config/                   Info.plist additions and entitlements
mockups/                  the design mockups every screen was matched against
scripts/                  sim, run, shots, test, uitest, release
SPEC.md                   the spec; HOME-CHECKS.md lists what to check at home
```

## Known limits

- Works only on the home Wi-Fi with the bridge; away from home it shows Bridge not
  reachable.
- No individual-light control or scenes in the UI (v1 scope).
- Siri phrases can carry only one value (the room), so brightness and warmth are asked
  for after the phrase.
- A few Hue details can only be confirmed with the real bridge (room-level color
  commands, scene recall at a set brightness); see [HOME-CHECKS.md](HOME-CHECKS.md).
