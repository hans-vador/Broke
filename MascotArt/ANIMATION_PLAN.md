# Broke — Mascot Animation Plan (Lottie)

Source of truth for the mascot/animation overhaul. Art = soft-3D "claymation"
fruit guardians (approved). Motion = **image-layer Lottie** rendered via
`lottie-ios`, with app state driving which clip plays.

Checkpoint baseline commit: `111eab8`.

---

## 1. Concept

The 8 fruits are a crew of **focus guardians**. When a focus session locks
(NFC pod tap / BLE room proximity) the guardian goes **on-duty** (alert, proud);
unlocked it is **idle** (calm). Blocking an app = the guardian throws up a
**stop-hand**.

## 2. Art assets (DONE)

Transparent PNG cutouts (idle pose), 1254px, in `MascotArt/cutouts/`:
`apple, orange, lemon, strawberry, pear, blueberry, watermelon, peach`.
Exact body colors match `FruitKind.bodyColor` in `DesignSystem.swift`.
Expression language defined in `MascotArt/expressions/strawberry-expressions.png`
(idle / on-duty / celebrate / blocking / sleepy / surprised).

Primary heroes (status + header + block screen): **strawberry, orange,
blueberry**. Locked hero = blueberry, unlocked hero = orange (per
`FruitPersona.forStatus`). Block-screen guardian = strawberry (face of Broke).

## 3. Animation states → app signals

| MascotState | App signal (existing code) | Notes |
|---|---|---|
| `.idle` | `model.displayedIsLocked == false` | calm breathing loop |
| `.onDuty` | `model.displayedIsLocked == true` | alert/proud loop |
| `.celebrate` | `lockAnimationTrigger` increments (ContentView:150) | one-shot, then settle to idle/onDuty |
| `.surprised` | `model.scanTag()` / `FocusPopup.tagReady`; `BLEProximityManager.isNear` flips true | short reaction, then resolve |
| `.blocking` | `FocusPopup.wrongTag` / `.podStillNear`; Shield extension | in-app = animated; shield = STATIC png |
| `.sleepy` | long idle (optional, later) | ambiance |

## 4. Lottie clip set (to author)

Each clip = a `.lottie`/`.json` embedding the relevant PNG(s) as image layers,
with keyframed transforms. Native Lottie shape layers add sparkles/shadow.

Per hero fruit (`strawberry`, `orange`, `blueberry`):
- `idle` — breathing bob + slow sway (loop)
- `onDuty` — tighter posture, subtle alert bob (loop)
- `celebrate` — hop + full spin + sparkle burst (one-shot) — port timing from
  `FruitMotionConstants` (jumpHeight, squashX/Y, spinDuration, sparkle).
- `surprised` — quick scale-pop + settle (one-shot)

Blocklist rows (all 8): reuse a single generic `idle` transform clip that swaps
in each fruit's cutout as the image layer (one clip, 8 image bindings) — keeps
file count low.

Motion reference values already exist in `DesignSystem.swift`
(`FruitMotionConstants`): bobHeight, swayAngle, jumpHeight, squashX/Y,
spinDuration=1.0s, settle damping. Reuse these so new motion matches the app's
established feel.

## 5. Expression handling in Lottie

Poses (idle vs on-duty vs celebrate face) differ in the baked render, so each
pose is its own full-body PNG image layer. Within a clip, cross-fade layer
opacity to switch pose; transform the whole composite for motion. (No separate
face rig for v1 — revisit only if a moment demands it.)

## 6. Integration tasks (Codex)

**Phase A — Assets (Claude drives via `codex exec` image-gen):**
- Generate per-state transparent sprites for the 3 hero fruits: `onDuty`,
  `celebrate`, `surprised`, `blocking` (idle already exists).
- Import all sprites into `Broke/Assets.xcassets` as image sets (or bundle
  resources referenced by the Lottie files).

**Phase B — Dependency + render layer (Codex):**
- Add `lottie-ios` via SPM to the Broke target.
- `MascotState` enum (cases above).
- `LottieMascotView: UIViewRepresentable` wrapping `LottieAnimationView`, with
  play/loop/one-shot + completion handling.
- Author the Lottie JSON clips (Phase 4 set) referencing the PNG assets.

**Phase C — Wire states (Codex):**
- Replace `FruitCharacter` / `LockCharacter` / `StatusAwareMascot` render bodies
  with `LottieMascotView` driven by `MascotState`.
- Map: `displayedIsLocked` → idle/onDuty; `lockAnimationTrigger` → celebrate;
  `scanTag`/`FocusPopup` → surprised/blocking; `BLE.isNear` → surprised→onDuty.
- Keep the existing `withAnimation` spring transitions around the swaps.

**Phase D — Block screen (Codex):**
- In `BrokeShieldConfiguration/ShieldConfigurationExtension.swift`, set the
  strawberry `blocking` PNG as the `ShieldConfiguration` icon (STATIC UIImage —
  the extension cannot run Lottie; keep image small, ~1x-2x, for memory limits).

**Phase E — Verify (Codex + build/run):**
- Build both targets; run in simulator; confirm each state plays and transitions
  are clean; tune timing vs. `FruitMotionConstants`.

## 7. Hard constraints (do not violate)

- Shield extension icon MUST be a static UIImage (memory-limited extension).
- Keep the app live-reactive: state selection stays driven by published vars;
  Lottie clip *choice/speed* responds to state, clips themselves are pre-baked.
- Match `FruitKind.bodyColor` exactly; keep the approved soft-3D family style.

## 8. Open / later
- `.sleepy` ambiance, per-fruit on-duty variants for all 8, optional layered
  face rig, dark-mode shadow treatment.
