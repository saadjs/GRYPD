# GRYPD

**GRYPD** is an open-source, local-only iOS companion to Apple Fitness+. It adds the strength-training tools Apple's own app is missing: filtering Strength workouts by muscle group, duration, and body focus, and logging the weight you lift, per workout and per move, to track progression over time.

Docs, features, and screenshots: **[grypd.saad.sh](https://grypd.saad.sh)**

## Features

- Filter Strength workouts by muscle group, duration, body focus, and equipment
- Log weight per workout and per individual move, with continuous history across workouts
- Set light/medium/heavy dumbbell tiers once: GRYPD auto-fills the right weight per move
- Progression charts per workout and per move
- 100% local: no account, no analytics, no sync. Everything lives on-device

See **[grypd.saad.sh/features](https://grypd.saad.sh/features.html)** for the full walkthrough with screenshots.

## Requirements

- Xcode with the iOS 26 SDK
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- An iOS 26 device or Simulator: the UI uses Liquid Glass APIs unavailable on earlier versions
- An active Apple Fitness+ subscription to actually play workouts (GRYPD itself needs no account)

## Building from source

The Xcode project is generated from `app/project.yml` and isn't checked in. From the repo root:

```bash
xcodegen generate --spec app/project.yml
xcodebuild -project app/GRYPD.xcodeproj -scheme GRYPD \
  -destination 'generic/platform=iOS Simulator' build
```

Or, wrapped in the `Makefile`:

```bash
make run    # generate, build, install, and launch on the Simulator
make test   # run GRYPDUnitTests
```

`make run` and `make test` use whichever Simulator is already booted, falling back to `iPhone 17 Pro`. Override with `DEVICE="iPhone 15 Pro"`.

The app is 100% native SwiftUI, with no third-party dependencies: only Apple frameworks (SwiftUI, Foundation, SwiftData). Catalog data is held in memory and joined with on-device SwiftData logs by a stable Apple catalog id.

## How the catalog is built

Apple doesn't expose a public API for Fitness+, so GRYPD builds its own catalog weekly by joining two sources:

- **Apple's public workout pages** provide canonical episode names, trainers, duration, and body focus.
- A **community-maintained, crowdsourced spreadsheet** ([SeaTable base](https://cloud.seatable.io/dtable/external-links/d08506897d274835bdab/?tid=1vDI&vid=0000)) provides the granular data Apple doesn't: muscle groups, per-workout moves, and dumbbells used.

The pipeline (`pipeline/`) unpacks a `.dtable` export, enriches every linked row, validates the result, and publishes a versioned, content-addressed JSON catalog to `dist/`. The app fetches that catalog read-only and refreshes its local copy only when it changes. Full explanation: **[grypd.saad.sh/data-source](https://grypd.saad.sh/data-source.html)**.

To rebuild the catalog from a fresh export:

```bash
make catalog                                       # expects "Weekly Workouts.dtable" in the repo root
make catalog DTABLE=/path/to/export.dtable          # or point at a specific file
```

## Repo layout

- `app/`: the iOS app (SwiftUI, generated Xcode project)
- `pipeline/`: Python data pipeline that builds the catalog from a SeaTable export
- `site/`: docs site source (Vite + React), built into `dist/` alongside the catalog JSON
- `dist/`: the published payload, catalog JSON plus docs site, served as-is from Cloudflare Pages
- `catalog/strength.json`: canonical Apple-enriched cache for linked Strength workouts

## Common tasks

```bash
make catalog   # rebuild catalog JSON from a SeaTable export
make site      # build the docs site and sync it into dist/
make run       # generate, build, install, and launch on the Simulator
make test      # run GRYPDUnitTests
make generate  # regenerate app/GRYPD.xcodeproj from app/project.yml
make py-check  # lint and test the Python pipeline
```

Run `make help` for the complete list, including release targets (`make beta`, `make archive`, etc.) used for TestFlight distribution.

## Privacy

No accounts, no analytics, no tracking. See **[grypd.saad.sh/privacy](https://grypd.saad.sh/privacy.html)**.

## Contributing

Issues and pull requests are welcome. See **[grypd.saad.sh/support](https://grypd.saad.sh/support.html)** for where to report bugs or request features. To contribute a missing workout's data, edit the community SeaTable base linked above.

## License

[MIT](LICENSE)
