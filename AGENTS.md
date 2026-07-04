# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## iOS app — build & test

The Xcode project is **generated** by XcodeGen from `app/project.yml` and is gitignored, so it must be regenerated before any build. The `Makefile` wraps `xcodegen` + `xcodebuild`, so from the repo root:

```bash
make generate   # regenerate app/GRYPD.xcodeproj from app/project.yml
make build      # generate + build for the iOS Simulator
make run        # generate + build + install + launch on the Simulator
make test       # run GRYPDUnitTests
```

`make run`/`make test` target whichever Simulator is already booted, falling back to `iPhone 17 Pro`; override with `make run DEVICE="iPhone 15 Pro"`. To run a single test, use `xcodebuild` directly with `-only-testing` (there is no `make` target for it):

```bash
xcodebuild -project app/GRYPD.xcodeproj -scheme GRYPD \
  -destination 'generic/platform=iOS Simulator' \
  test -only-testing:GRYPDUnitTests/WorkoutFilterTests/<method>
```

Target: iOS 26, Swift 5. Scheme and target are both `GRYPD`; tests are `GRYPDUnitTests`. The app intentionally requires iOS 26 because the UI uses Liquid Glass APIs.

## TestFlight release

Releases go through the `Makefile` (which wraps `xcodegen` + `xcodebuild` + `altool`). One-time setup: copy `.env.example` to `.env` (gitignored) and fill in `API_KEY_ID`, `API_ISSUER_ID`, and `API_KEY_PATH` for an App Store Connect API key (Admin or App Manager role). The Makefile `-include`s `.env`, so the upload targets need no arguments once it's filled in.

To cut a release:

1. **Bump the version** in `app/project.yml` — `MARKETING_VERSION` (e.g. `1.1`) and/or `CURRENT_PROJECT_VERSION` (the build number, must increase for every TestFlight upload). Commit it.
2. Run the full pipeline from the repo root:

```bash
make beta   # archive → export .ipa → upload to TestFlight
```

`make beta` chains `archive` (Release archive at `app/build/GRYPD.xcarchive`), `export` (writes `app/build/GRYPD.ipa` via a generated `ExportOptions.plist`, team `2ZPA772V9V`, `app-store` method), and `upload` (`xcrun altool --upload-app`). The individual targets (`make archive` / `export` / `upload`) can be run separately, and `make organizer` opens the archive in Xcode Organizer for a manual **Distribute App** instead.

## UI: Dynamic Type + native-only

- **Never** use `Font.system(size:)` or `.font(.custom(...))` — those sizes are frozen and ignore the user's text-size setting. Use the helpers in `app/GRYPD/DesignSystem/ScaledFont.swift`: `.scaledFont(_:weight:design:relativeTo:)`, or the shared roles `sectionHeaderFont()` / `primaryLabelFont(weight:)`. Add new roles there rather than hardcoding sizes anywhere else.
- **100% native SwiftUI only — this is a constitution, not a preference.** No third-party UI libraries or SPM dependencies (only Apple frameworks: SwiftUI, Foundation, SwiftData, Observation). **No hand-rolled custom controls either:** if the system ships a control for the job, you use it verbatim — `Button` with `Image(systemName:)` and `Label`, system `ToolbarItem`/`ToolbarItemGroup` for nav-bar actions, `NavigationStack`/`navigationDestination` for navigation, `List`/`Form`/`Section` for rows, `Menu` for menus, `.sheet`/`.fullScreenCover` for presentation, `Toggle`/`Slider`/`Stepper`/`Picker`/`DatePicker` for inputs. Never build a bespoke button shape, custom nav bar, custom back button, custom tab bar, or custom sheet chrome when the native equivalent exists. The system controls are what give you correct Dynamic Type, VoiceOver, gestures (e.g. edge-swipe-to-pop), and platform look for free — reimplementing them throws all of that away.
- Accent color: use `Color.brand` (the `AccentColor` asset) as a fill paired with `Color.onBrand` (black) — never white on the green. See `app/GRYPD/DesignSystem/Brand.swift`.
- **No Apple Fitness+ imagery — ever.** Fitness+ artwork (trainer photos, episode thumbnails, mzstatic URLs) is Apple-copyrighted and unlicensed for third-party apps. Never add `AsyncImage`/remote image fetches for workout art, and never reintroduce an `imageTemplate`/image-URL field to the model or pipeline. Each workout's visual identity is generated 100% natively by `WorkoutArt` / `WorkoutTile` / `WorkoutHeroBackground` in `app/GRYPD/DesignSystem/WorkoutArtwork.swift` (per-trainer gradient + body-region SF Symbol). Extend that instead.

## UI: One consistent design system

Every screen must look like the same professionally-made app — same layout skeleton, same surfaces, same hero/backdrop, same section headers. Consistency is **structural, not by-eye**: compose the shared primitives in `app/GRYPD/DesignSystem/AppSurfaces.swift` instead of hand-rolling equivalents. Never redefine a card background, section header, hero, or corner radius locally in a feature file.

- **Canvas:** every screen is `Color.black.ignoresSafeArea()`. Accent is `Color.brand` on black (see the rule above).
- **Card surfaces:** use `.cardSurface(radius:fillOpacity:strokeOpacity:)` (faint white fill + hairline stroke). Brand-tinted feature panels use `.featurePanel()`. Radii come from `AppRadius` (`.card` 18 / `.panel` 22 / `.feature` 26) — never a raw literal.
- **Section headers:** use `SectionHeader("Title", accessory:)` (`.count(Int)` in lime, or `.text(String)` muted). Do not build a title+`sectionHeaderFont()` HStack by hand.
- **Two page archetypes, and only two:**
    - _Hero-detail_ (workout detail, logged session) is built on `HeroDetailLayout` + `DetailHero`, with the generative `WorkoutHeroBackground`. The full-bleed hero/backdrop belongs to **detail pages only**.
    - _Tab-root_ (Browse, History, Progress, Settings) is a `NavigationStack` with a large `navigationTitle` and carded content — **no hero backdrop**.
- **Type:** only the `ScaledFont.swift` roles (`heroTitleFont()`, `sectionHeaderFont()`, `primaryLabelFont()`, `.scaledFont(...)`). See the Dynamic Type rule above.
- **Primary action buttons:** every full-width call-to-action (e.g. _Let's Go_, _Log Workout_, _View Workout_) uses **one shared height + label font** via `.primaryActionLabel()` (defined in `AppSurfaces.swift`). Apply it to the button/`NavigationLink` label, then pair it with a native button style — `.buttonStyle(.borderedProminent)` for the brand-tinted primary, `.buttonStyle(.bordered)` for the secondary white — plus `.buttonBorderShape(.capsule)`. **Never** hardcode a button `.frame(height:)` or a per-button label font in a feature file; that is exactly how two buttons of the same kind drift to different heights. When a new CTA needs different metrics, change the shared token, don't fork one.

When a shared role is missing, add it to the DesignSystem layer and reuse it — do not fork a one-off in a feature view.

## UI: Apple-platform conventions

Native iOS users expect controls to behave the way the system frameworks define them. Match Apple's documented behavior, not a hand-rolled approximation:

- **Fetch the official Apple docs before any UI-behavior change.** Use the `find-docs` skill (Context7 CLI, library `/websites/developer_apple_swiftui`) — your training data is stale for SwiftUI API signatures and placements. Verify modifier names, `ToolbarItemPlacement` values, `PresentationDetent` options, etc. against current docs before writing code. Do not guess.
- **Pinned top controls on hero-detail screens.** The hero-detail screens (`WorkoutDetailView`, `LogDetailView`) use a **transparent navigation bar** (`.toolbarBackground(.hidden, for: .navigationBar)` + `.toolbarColorScheme(.dark, for: .navigationBar)`) so the hero bleeds under the status bar, exactly like Apple's own full-bleed detail screens (e.g. Photos). The bar is **kept in the hierarchy** (never `.toolbar(.hidden, for: .navigationBar)`) so Apple's native back chevron (leading) and the interactive edge-swipe-to-pop gesture both work unchanged — do not hide the nav bar or back button. The `+` / ellipsis-menu actions are plain `Image(systemName:)` labels in a `ToolbarItemGroup(placement: .topBarTrailing)` (supplied via `HeroDetailLayout`'s `controls`), which Apple pins to the bar so they never scroll away. Never reintroduce custom circle-button overlays or a custom back button.
- **Checkmarks are always brand lime.** Any `checkmark` SF Symbol (`.checkmark`, `.checkmark.circle`, `.checkmark.circle.fill`) used as a status/completion affordance is `Color.brand` — on a filled brand circle it is `Color.onBrand` (black), matching the `Color.brand` + `Color.onBrand` pairing rule. Never render a checkmark in default/white/orange. The only exception is a `Menu` selection checkmark, which inherits the app's `AccentColor` (already brand) automatically.
- **One bottom-sheet presentation, defined once.** Every `.sheet` uses `.sheetPresentation()` (defined in `AppSurfaces.swift`): `presentationDetents([.large])` + `presentationDragIndicator(.visible)`. Never set `presentationDetents`/`presentationDragIndicator` inline in a feature file — that lets sheets drift to different heights. A new sheet just gets `.sheetPresentation()`.

## Code comments

Write comments for a reader who is **new to the codebase but already familiar with the project's goal**. Assume they know what a Fitness+ companion app is and what the feature is for — don't restate the obvious or narrate what the code plainly says. Do explain the things a newcomer can't infer from the code alone: why a non-obvious approach was chosen, which invariant a block protects, what a workaround is compensating for, and how a piece connects to the rest of the system.

## Data pipeline

Python 3, stdlib-only, run from repo root: `make catalog`. This unpacks `Weekly Workouts.dtable`, enriches linked rows, assembles the versioned content-addressed `dist/` payload (served as-is from Cloudflare Pages), syncs bundled app resources, and prunes stale addressed files. `make py-check` lints and runs the pipeline tests. See `README.md` for the full flow.

The pipeline deliberately does **not** store or publish Apple artwork (see the UI hard requirement above): `enrich.py` skips the `artworks` field, and `assemble.py` strips any lingering `imageTemplate` before writing `dist/`. Don't re-add it.
