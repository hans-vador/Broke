# Strawberry Lottie Prototype Result

## Files

Changed:

- `Broke.xcodeproj/project.pbxproj` — added the `lottie-ios` SPM reference/product to the Broke app target and the shield PNG to the extension resources.
- `Broke/ContentView.swift` — replaced only the status-card hero slot with the clearly marked strawberry `LottieMascotView` prototype. Existing `StatusAwareMascot`, `FruitCharacter`, and `LockCharacter` code remains untouched in `DesignSystem.swift`.
- `BrokeShieldConfiguration/ShieldConfigurationExtension.swift` — uses the static strawberry blocking PNG as the shield icon.

Added:

- `Broke.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `Broke/LottieMascotView.swift`
- `Broke/MascotLottie/strawberry_idle.json`
- `Broke/MascotLottie/strawberry_onDuty.json`
- `Broke/MascotLottie/strawberry_celebrate.json`
- `Broke/MascotLottie/strawberry_surprised.json`
- `Broke/MascotLottie/strawberry_blocking.json`
- `Broke/MascotLottie/images/strawberry_idle.png`
- `Broke/MascotLottie/images/strawberry_onduty.png`
- `Broke/MascotLottie/images/strawberry_celebrate.png`
- `Broke/MascotLottie/images/strawberry_surprised.png`
- `Broke/MascotLottie/images/strawberry_blocking.png`
- `BrokeShieldConfiguration/StrawberryBlocking.png` — downsampled to 360×360 for the memory-limited extension.
- `MascotArt/PROTOTYPE_RESULT.md`

## Dependency

`lottie-ios` resolves to **4.6.1** (`f4db77d7feacba0c2360b84a40c38a6ce8ff399d`) with an SPM requirement of `4.6.1 ..< 5.0.0`.

## Clip structure

- `idle`: 30 fps, 4-second loop; ±12 px breathing bob and ±1.15° sway, matching `bobHeight`, `bobSpeed`, `swayAngle`, and `swaySpeed`.
- `onDuty`: 30 fps alert loop; idle-to-on-duty image-layer opacity cross-fade, followed by a tighter ±7 px bob and ±0.5° sway. The wrapper plays the entry once, then loops frames 8–60 so the pose cross-fade does not repeat.
- `celebrate`: 60 fps, 1.6-second one-shot; anticipation squash, 171 px hop based on `jumpHeight`, a full 360° spin over exactly 1.0 second, native Lottie star/ellipse shape-layer sparkles, landing squash, and damped settle keyframes. Idle and celebrate sprites cross-fade in a precomposition.
- `surprised`: 60 fps, 0.7-second one-shot; idle-to-surprised cross-fade, quick 82%→112% scale pop, then decreasing position/rotation/scale oscillations to neutral.
- `blocking`: supplemental subtle loop so every required `MascotState` has a valid app-side clip; the Shield extension uses only its static PNG and does not link Lottie.

`MascotState` contains `.idle`, `.onDuty`, `.celebrate`, `.surprised`, and `.blocking`. Looping states loop; one-shots return through the coordinator to the latest idle/on-duty base state. `ContentView` maps `displayedIsLocked` to idle/on-duty and fires celebrate whenever `lockAnimationTrigger` changes.

Xcode's synchronized group flattens these resources into the built app bundle. The loader intentionally resolves JSON and images from `Bundle.main`; a post-build check confirmed every JSON/PNG reference exists in the built app and the shield PNG exists in the built extension.

## Build result

**SUCCESS** — `xcodebuild` completed for Debug with the iOS Simulator 26.5 SDK, building both Broke and `BrokeShieldConfiguration` and ending with `** BUILD SUCCEEDED **`.

The successful generic-Simulator build emitted no Swift compile warnings. Remaining tool warnings were Xcode selecting the first of multiple simulator destinations and metadata extraction being skipped because the app does not depend on `AppIntents.framework`. A later explicit-device probe could not access CoreSimulator services under the workspace sandbox; it did not expose a code/build error and the app was not run.

## Human visual verification

Per instruction, the app was not launched. A human still needs to verify sprite framing, pose cross-fades, hop/spin/sparkle timing, settle feel, state transitions under rapid lock changes, and the blocking icon's scale/legibility on a real Screen Time shield.

## Framing fix

`LottieMascotView` now returns SwiftUI's proposed width and height from `sizeThatFits`, with aspect-aware defaults only when a dimension is unspecified.
The `LottieAnimationView` is pinned to a clipping container with low hugging and compression-resistance priorities, preventing its 1254×1254 intrinsic size from expanding layout.
The inner animation remains centered with `scaleAspectFit`, while all coordinator loop and one-shot playback behavior is unchanged.

## Clip decode fix + gallery

- `LottieMascotView.Coordinator.load` no longer asserts or clears/stops a working animation when `LottieAnimation.named` returns `nil`. It logs the missing clip, preserves any animation already playing, and makes a non-recursive idle fallback attempt only when the view has no animation. Looping states still loop, one-shots still return to the latest base state, and the 1254×1254 framing fix remains intact. The obsolete on-duty frame-8 cross-fade entry handling was removed because on-duty is now a complete single-layer loop.
- Rebuilt `strawberry_onDuty.json`, `strawberry_celebrate.json`, and `strawberry_surprised.json` with a 1254×1254 canvas, exactly one image asset using that state's real PNG filename, and exactly one top-level `ty:2` image layer. They contain no precomps, nested compositions, idle asset, or pose cross-fade. On-duty is a tight alert-breathing loop. Celebrate is a one-shot with anticipation squash, a `jumpHeight`-based hop, a 360° rotation from frame 8 through frame 68 (exactly 1.0 second at 60 fps), native Lottie shape-layer sparkles, landing squash, and damped settle. Surprised is a one-shot 85%→112% pop with decreasing scale/position/rotation oscillations back to neutral.
- Added `MascotGalleryView` entirely behind `#if DEBUG`, plus a new gallery button beside the existing dev lock and palette buttons in `ContentView`. Its segmented picker switches among idle, on-duty, and blocking base states; Celebrate and Surprised buttons fire either one-shot. Release builds contain neither the gallery screen nor its entry button.
- Revalidated all five JSON files and their referenced bundled PNG names. A Debug generic iOS Simulator build using SDK 26.5 compiled the app and shield extension and ended with `** BUILD SUCCEEDED **`.

## Preview env hook

Debug builds can launch directly into a large, centered mascot preview by setting `MASCOT_PREVIEW` to `idle`, `onDuty`, `celebrate`, `surprised`, or `blocking`. For Simulator launches, pass it through with a command such as `SIMCTL_CHILD_MASCOT_PREVIEW=celebrate xcrun simctl launch <device> <bundle-id>`. Celebrate and surprised replay automatically; an unset or invalid value launches the normal app.

## Demo mode

Debug builds can show the normal `ContentView` status card automatically cycling through the real lock-state path by launching with `MASCOT_DEMO=1`. For Simulator launches, pass it through with `SIMCTL_CHILD_MASCOT_DEMO=1 xcrun simctl launch <device> <bundle-id>`. The loop starts idle for about 3 seconds, locks for about 4 seconds (celebrate then on-duty), unlocks back to idle, and repeats. Demo mode bypasses Screen Time/ManagedSettings work on the Simulator and takes precedence over the `MASCOT_PREVIEW` gallery hook.

## Layered idle rig

- Replaced the single-image strawberry idle clip with a decode-safe 1254×1254 rig containing five independent top-level image layers (`legL`, `legR`, `body`, `armL`, `armR`) and two optional top-level shape layers for the blink. There are no precomps or nested compositions.
- Measured opaque bounds before assembly: body `(263, 191, 720×945)`, arm `(469, 287, 290×718)`, and leg `(430, 249, 392×764)`. The tuned static verification render is `MascotArt/layers/strawberry/_assembled_preview.png`; its reproducible assembly utility is alongside it as `assemble.swift`.
- Added exact copies of the three supplied layer PNGs to `Broke/MascotLottie/images/` as `strawberry_body.png`, `strawberry_arm.png`, and `strawberry_leg.png`. The unmirrored source supplies the mascot's right-side limb and negative X scale supplies the left-side limb.
- The seamless 3-second, 60 fps idle combines 6-point anti-correlated body squash/stretch, ±12 px bob, ±1.5° sway, opposing eased arm swings up to ±8.5° with phase lag, subtle alternating leg weight shifts, and a 0.12-second blink once per loop. Arm anchors are at `(611, 287)` and leg anchors at `(627, 249)`, the measured top attachment ends.
- `LottieMascotView` required no code change: `.idle` already resolves to `strawberry_idle` and the existing bundle image provider resolves the new flattened PNG resources. All other state clips remain unchanged.
- A Debug build for `generic/platform=iOS Simulator` compiled the app, Lottie package, and shield extension and ended with `** BUILD SUCCEEDED **`.

## Idle rig polish

- Replaced the bundled `strawberry_leg.png` with the corrected body-red, stubbier leg art and updated the measured leg attachment anchor to the exact opaque top edge at `(621, 419)`.
- Reordered the decode-safe top-level layers so the body masks the arm and leg attachment ends, tucked the shoulders inward and hips upward, reduced limb travel, and kept all rotations pivoting at their attachment ends. The rig still contains only five top-level image layers and two blink shape layers, with no precomps.
- Polished the seamless 3-second idle with breathing, bob, and sway intact; arms now follow the body with a few frames of springy secondary lag and gentler swing, while the feet add a subtle down-beat squash. The quick frame 154–161 blink remains clearly visible once per loop.
- Rebuilt `MascotArt/layers/strawberry/_assembled_preview.png` from the corrected art and tightened placements so every limb reads as firmly connected.
- Revalidated the 3-second loop and decode-safe layer structure, then built Debug for `generic/platform=iOS Simulator`; `xcodebuild` ended with `** BUILD SUCCEEDED **`.

## Cohesion fix

- Recolored `arm.png` and `leg.png` with a deterministic luminance-histogram remap onto the red-only palette sampled from `body.png`, excluding the crown, seeds, eyes, and mouth. The limb shading and clay texture remain intact, but limb hue and saturation now come exclusively from actual body-ramp pixels. The corrected assets are mirrored exactly in `Broke/MascotLottie/images/`.
- Pushed both shoulder anchors 16 px inward and 10 px upward, pushed both hip anchors 8 px inward and 18 px upward, kept the body above every limb root, and reduced arm/leg rotation extremes. The lively breathing, bob, sway, arm lag, weight shift, and blink remain, with deeper overlap throughout the loop.
- Rebuilt `MascotArt/layers/strawberry/_assembled_preview.png` from the corrected palette and tightened placements. Revalidated five top-level image layers plus two top-level blink shape layers with no precomps, then built Debug for `generic/platform=iOS Simulator`; `xcodebuild` ended with `** BUILD SUCCEEDED **`.

## Appearance customization

- Expanded the color-scheme swatches to Strawberry, Citrus, Sunset, Blueberry, Grape Soda, Matcha, Bubblegum, Midnight, and Mono. Each preset defines cohesive primary, locked, accent pink, accent blue, surface, text, muted, and signal colors, including light foreground colors for Midnight's deep surfaces.
- Promoted customization into a user-facing Appearance sheet from the palette button in the main header. Preset swatches apply live, while the existing mascot picker remains available.
- Added independent persisted controls for card corners (Rounded or Sharp), layout density (Cozy or Compact), background (Soft blobs or Plain), block-list mascots (On or Off), and bold headings (On or Off). Defaults preserve Broke's current rounded, cozy, playful look.
- Routed the preferences through `DesignSettings` and `DesignTokens`, so cards, spacing, hero sizing, backdrop decoration, block-list art, and heading weights update immediately without disturbing the lock flow or the DEBUG `DesignDebugPanel`.
- Type-checked the complete app module and compiled/linked it with `xcodebuild` for the iOS Simulator 26.5 SDK; verification ended with `** BUILD SUCCEEDED **`.
