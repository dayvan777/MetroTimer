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
`Shared/` is compiled into **both** the app and the widget target — and so is
`kyiv_metro.json`, because `MetroRepository.init` calls `fatalError` when the
file is missing from its bundle.

The build number is kept from the existing `project.pbxproj`, so regenerating
never changes it. Raise it explicitly before every App Store Connect upload —
each build number can be uploaded only once:

```bash
MT_BUILD=8 python3 Scripts/gen_pbxproj.py
```

`App/MetroTimer.entitlements` is wired into the app target by default. A free
Personal Team cannot sign the Time Sensitive Notifications entitlement, and
without it iOS silently downgrades `.timeSensitive` notifications — so the
"next stop is yours" alert stops breaking through Focus modes, which is the
one scenario the app exists for. On a free team, generate with
`MT_NO_ENTITLEMENTS=1`. On the paid account, verify the signed bundle with:

```bash
codesign -d --entitlements - build/Build/Products/Release-iphoneos/MetroTimer.app
```

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

The five App Store slides (1320×2868) are assembled in Figma and exported to
`AppStore/screenshots/figma/`; the site uses smaller copies in `AppStore/site/img/`.
The earlier script-built frames were retired in `d4cc148`; the script is still in
history: `git show d4cc148^:Scripts/make_store_frames.py`.

Before every re-shoot, read each slide, small print included, for price references
(«безкоштовно», "free", discounts): App Review rejects them under Guideline 2.3.7.

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
| `Tests/` | Unit tests over the core, hosted in the app process |
| `Scripts/` | Data and project generators |
| `AppStore/` | Listing metadata, privacy policy, screenshots, support page source |
| `docs/` | This file, plus `GPS.md` and `READINESS.md` (both in Russian) |
