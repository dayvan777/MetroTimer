# Building and working on the project

Everything a contributor needs that does not belong in the README.

## Requirements

- Xcode with an iOS 16.1+ SDK, macOS
- Python 3 — only for regenerating the Xcode project and the metro data file
- No Homebrew, no XcodeGen, no CocoaPods, no SPM dependencies

`MetroTimer.xcodeproj` is committed, so a plain clone opens and builds.

## Build and test

```bash
xcodebuild -project MetroTimer.xcodeproj -scheme MetroTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test
```

The test bundle is hosted inside the app process (`TEST_HOST`), so
`MetroRepository` reads the real bundled `kyiv_metro.json` rather than a fixture.

## Generators

The Xcode project and the metro data file are both generated. Neither generator
needs network access — the derived official values are baked in as literals.

```bash
python3 Scripts/gen_pbxproj.py
```

Rebuilds `MetroTimer.xcodeproj/project.pbxproj`. The file lists live at the top
of the script: add or remove a source file there, then re-run. Note that
`Shared/` is compiled into **both** the app and the widget target, while
`kyiv_metro.json` ships only with the app.

```bash
python3 Scripts/gen_metro_json.py
```

Rebuilds `App/Resources/kyiv_metro.json` — lines, stations, segments, transfers,
headways and service hours.

### Re-deriving the official data

Only needed when the city publishes a new timetable. Both scripts print Python
literals that get pasted back into `gen_metro_json.py`.

```bash
python3 Scripts/derive_official_times.py stoptimes.json
```

Per-segment running and dwell times, derived from first/last train departure
times at each station in both directions.

```bash
python3 Scripts/derive_official_service.py intervals.json stoptimes.json
```

Headways per line, hour and day type, plus first/last train per station and
direction.

Source layers (Kyiv open data portal, dataset
[«Розклад руху міського електричного та автомобільного транспорту»](https://data.kyivcity.gov.ua/dataset/rozklad-rukhu-miskoho-elektrychnoho-ta-avtomobilnoho-transportu-dep-transport)):

```bash
BASE="https://gisserver-stage.kyivcity.gov.ua/mayno/rest/services/KYIV_API/transport_public/MapServer"
curl -A "Mozilla/5.0" "$BASE/13/query?where=1%3D1&outFields=*&f=json" -o stoptimes.json
curl -A "Mozilla/5.0" "$BASE/14/query?where=1%3D1&outFields=*&f=json" -o intervals.json
```

## Store assets

```bash
python3 Scripts/make_store_frames.py
```

Builds the framed showcase slides in `AppStore/screenshots/framed/` from raw
simulator captures.

## Merging calibration from several devices

```bash
python3 Scripts/merge_calibration.py
```

Field testing produces one `calibration.json` per device (exported from the
Calibration screen). This merges them, weighting by sample count.

## Debug hooks

Compiled out of Release builds.

Start a trip with no UI interaction:

```bash
SIMCTL_CHILD_MT_SKIP_NOTIF_AUTH=1 xcrun simctl launch booted ua.vlad.MetroTimer -MTStartFrom akademmistechko -MTStartTo khreshchatyk
```

Other launch arguments:

| Argument | Effect |
|---|---|
| `-MTAdjust <n>` | Apply a ±n correction to the active trip |
| `-MTAnchor <i>` | Fast-forward the trip to route event `i` |
| `-MTPreselectFrom` / `-MTPreselectTo` | Preselect stations for screenshots |
| `-MTSkipOnboarding 1` | Suppress the first-run card |
| `-MTPreviewOffset <seconds>` | Shift "now" to test service-hour warnings |
| `-MTForceAlert 1` | Force the air-raid banner |
| `-MTForceAlertFail 1` | Force the "source unavailable" banner |

`MT_SKIP_NOTIF_AUTH` (an environment variable, not a launch argument) skips the
notification permission prompt.

## Repository layout

| Path | Contents |
|---|---|
| `App/` | SwiftUI screens and app-only services |
| `Shared/` | Compiled into both app and widget: models, planner, trip engine, strings |
| `Widget/` | Live Activity UI — Dynamic Island and Lock Screen |
| `Tests/` | 28 tests over the core |
| `Scripts/` | Data and project generators, store slides |
| `AppStore/` | Listing metadata, privacy policy, screenshots, support page source |
| `docs/` | This file, plus `GPS.md` and `READINESS.md` (both in Russian) |
