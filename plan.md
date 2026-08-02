# BulletHell — Touhou-ification Master Plan

Goal: evolve the current engine (4 stages, DSL-scripted patterns, multi-phase bosses,
procedural art/audio) into a full Touhou-style game: playable characters with real art
and animations, sprite-based directional bullets and lasers, spell card presentation,
stage background art, composed music + sound effects, and a proper full-screen menu
system (title, character select, practice, score, music room, options).

This document is written so a future agent can start any phase **without rereading the
whole codebase**. Section 1 is the crash course; section 2 is the invariants that will
bite you if ignored; section 3 is the asset layout to converge on; sections 4+ are the
phases, each with concrete tasks, file pointers, and acceptance criteria.

Supersedes the remaining items in `roadmap.md` (Tiers 1–3 there are done).

---

## 1. Architecture crash course (read this, skip rereading the code)

**Toolchain**: Haxe 4.2.0, lime 8.0.2, openfl 9.2.2, hxcpp 4.3.2, MSVC 64-bit.
Targets: `lime build windows` (primary) and `lime build html5` (fast smoke test).
Everything is frame-based at 60 fps (`<window fps="60">` in `project.xml` — native
defaults to 30 without it). Never use wall-clock time for gameplay.

**Coordinate system**: logical stage is 1920x1080 (`DisplaySettings.LOGICAL_W/H`),
scaled by `StageScaleMode.SHOW_ALL` to any window. The *playfield* levels are authored
against is 1800x1080 (`DisplaySettings.FIELD_W/H`), centred in the stage via the static
`Main.world` sprite (offset `FIELD_X/FIELD_Y`). Every gameplay object (enemies, bullets,
items, player) must be a child of `Main.world`; UI (HUD, panels, dialogue) parents to
`Main` directly and lays out against the full 1920 stage. Culling/spawn/clamping must
use `Main.fieldWidth/fieldHeight`, **never** `stage.stageWidth` (live stage size changes
with the window and caused the old fullscreen-minimize culling bug).

**Frame loop**: single `ENTER_FRAME` in `Main.everyFrame` (Source/Main.hx:851) drives
`background.update()`, `AudioManager.tick()`, `player.updateMovement()`,
`itemManager.update()`, `stageManager.update()`, `enemyManager.update()`, boss bar and
HUD tracking. Bullets are updated centrally by `CollisionManager` (bullets must never
own ENTER_FRAME listeners — self-removal during broadcast skips the next listener's
update). A few UI classes (DialogueManager, Player cosmetic spin) still have their own
ENTER_FRAME but check `Main.gamePaused` first. Any new per-frame logic must check
`Main.gamePaused` (in-run ESC pause) — that static flag is how the whole sim freezes.

**Game flow today**: `Main` has a two-state `GameState` enum (`Paused` = title/game-over
panel showing, `Playing` = in run). The "title screen" is just text in the message panel
(`Main.titleText()` at Source/Main.hx:565, key handling in `keyDown` at Source/Main.hx:689).
Options/pause screens reuse the same panel. This is the thing Phase 6 replaces.

**Content pipeline**: levels/patterns are authored as JS in `tools/src/*.js` using the
DSL in `tools/bh/index.js` (`S.` shot commands, `M.` movement, `level/wave/spawn/boss/
phase/say/pattern` helpers), compiled by `node tools/compile.js` to
`Assets/levels/*.json` + `Assets/patterns/*.json`, statically checked by
`tools/bh/validate.js`. The engine parses that JSON via `Source/Manager/PatternLoader.hx`
/ `LevelData.hx` typedefs / `Source/Shot/CommandRegistry.hx`. **Any new JSON field needs:
(1) a LevelData typedef entry, (2) engine support, (3) a DSL helper in tools/bh/index.js,
(4) validator knowledge in tools/bh/validate.js** — the validator warns on unknown
fields, so skipping (4) makes `--check` noisy or fails.

**Release sealing**: `Assets/levels` and `Assets/patterns` JSON is sealed into `.dat`
(`tools/seal.js`, reader `Source/Manager/AssetSeal.hx`/`SecureAssets.hx`); release
builds go through `node tools/release.js windows`. Everything else in `Assets/`
(sprites.json, art, fonts — and any new art/bgm/sfx dirs) ships as-is via the
`<assets path="Assets" ... exclude="levels|patterns" />` line in project.xml. New
sealed-content dirs would need the same include/exclude dance — prefer keeping new data
(characters, backgrounds, bgm manifests) unsealed.

**Key classes** (all under `Source/`):
- `Manager/EnemyManager.hx` — spawning (`spawnEnemy`, `spawnBoss`:106), central enemy
  update, boss phase orchestration (wires `BossEnemy.onPhaseDepleted`: field wipe, pattern
  swap, `startNextPhase`). `getActiveBoss()` is polled by Main for the boss bar.
- `Manager/CollisionManager.hx` — owns bullet lists + updates, circle-vs-circle hit
  tests, graze (`onGraze`), `clearEnemyBullets()`, `clearAllBullets()`,
  `damageAllEnemies()`, kill routing (`onEnemyKilled` → score + item drops).
- `Manager/StageManager.hx` — sequences `Main.STAGES` (Source/Main.hx:124), callbacks
  `onStageBegin` (theme + music), `onStageMessage`, `onPlayDialogue`, `onAllStagesCleared`;
  `startRun(index, single)` powers practice mode.
- `Manager/LevelManager.hx` — wave timing within a stage (frame-accumulated `levelTime`).
- `Manager/SpriteLibrary.hx` — data-driven skins from `Assets/sprites.json`
  (`{skins: {name: {enemy: SpriteDef, bullet: SpriteDef}}}`, SpriteDef =
  `{source, rect?, scale?}`). Caches BitmapData. This is the extension point for all
  new sprite features.
- `Bullet/BulletEnemy.hx` — bullet flight from a cloned `ShotPrototype` (direction,
  speed, accel, angular velocity, lifetime, size, bind modes, per-bullet sub-scripts).
  Cosmetic spin at Source/Bullet/BulletEnemy.hx:292 (`rotation = salt + ROTATION_SPEED *
  age / 60`) — Phase 3 replaces this with facing modes.
- `Enemy/BossEnemy.hx` — phases with per-phase health (`phaseHealth`), timeouts
  (`timeoutFrames`), transition invuln. Phase data = `LevelData.BossPhaseData`
  (name/health/timeoutFrames/pattern/patternConfig/script/movementScript). A "phase"
  is already 90% of a Touhou spell card — Phase 4 builds the presentation on top.
- `Player/Player.hx` — movement/focus/lives/invincibility. Static art, cosmetic spin at
  Source/Player/Player.hx:244 (must go when real character art lands).
- `Player/PlayerShootingPattern.hx` — 3 shot types (Spread/Pierce/Homing), power
  0.00–4.00 (`MAX_POWER`), tiered volleys, per-type cadence/damage.
- `Manager/AudioManager.hx` — 100% synthesized audio today (16-bit WAV built in memory,
  loaded via `loadCompressedDataFromByteArray`). API: `init/playMusic(stageNumber)/
  stopMusic/toggleMusicMuted/nudgeMusicVolume/setMusicDucked/tick`, SFX:
  `sfxFire/sfxPlayerDeath/sfxBomb/sfxItemPickup`. Phase 5 swaps internals, keeps API shape.
- `Manager/GameSettings.hx` — difficulty (Easy/Normal/Hard/Lunatic), lives/bombs,
  `scaleHealth`, `bulletSpeedMultiplier` (applied ONLY in `BulletEnemy.updateVelocity`
  so scripts keep authored speeds), `practiceStage`.
- `Manager/DisplaySettings.hx` — windowed/fullscreen (faked borderless fullscreen — see
  invariants), JSON persistence to `lime.system.System.applicationStorageDirectory`
  (Source/Manager/DisplaySettings.hx:204-251). **Copy this pattern for score/unlock saves.**
- `UI/HUD.hx` (score/lives/bombs/power/shot-type, proximity fade via `trackPlayer`),
  `UI/BossHealthBar.hx` (polled `track(boss)`), `UI/DialogueManager.hx` (portrait +
  typewriter, `DialogueEntryData` = speaker/text/portrait/side), `UI/StageBackground.hx`
  (procedural gradient + 3 parallax circle layers, `setTheme(stageNumber)`).

**Verification loop** (run after every change; all must stay green):
```sh
node tools/compile.js --check                      # DSL compile + validate all JSON
haxe -cp Source -cp Tests -main TestShot --interp  # shot-engine unit tests
lime build html5                                   # fast type-check + smoke build
lime build windows                                 # the real target
```
Playtest: launch `Export\windows\bin\BulletHell.exe` **with that folder as working
directory** (`Start-Process -WorkingDirectory`), else white screen. Automated
screenshot: sleep ~6s after launch then `CopyFromScreen(0,0,0,0,1920x1080)` — works
because fullscreen is borderless-composited (do NOT reintroduce real SDL fullscreen,
and don't poke the window with SetForegroundWindow — it has crashed the process).

---

## 2. Invariants and known landmines (violating these re-breaks fixed bugs)

1. **Audio**: never use `Sound.loadPCMFromByteArray` — float32 PCM is silently
   unplayable on both targets (lime 8.0.2). In-memory audio must be 16-bit WAV via
   `loadCompressedDataFromByteArray`. For files, native lime decodes **OGG Vorbis and
   WAV only — MP3 does not play on the windows target**. Author BGM as `.ogg`.
2. **Fullscreen** is faked: `borderless` + resize to display bounds with a deliberate
   1px overhang (`bounds.y - 1`, `height + 2`) so DWM keeps compositing (screenshot
   capture depends on it). `borderless="true"` must stay in project.xml (runtime setter
   can't drop a title bar). Never set `window.fullscreen = true`.
3. **Fonts**: every TextField must use `Main.uiFont` (bundled NotoSans) with
   `embedFonts = true`. System font names silently render nothing on native. The font
   has no ▼-style glyphs — draw indicators with vector graphics (see
   DialogueManager.advanceArrow).
4. **Timing**: frame counts, not `Lib.getTimer()`. Difficulty bullet-speed scaling is
   applied only at velocity integration (`BulletEnemy.updateVelocity`) — keep it there.
5. **`openfl_dpi_aware`** haxedef must stay (back-buffer sizing), `--no-traces` for
   release (traces are a real per-frame cost).
6. **Bullet updates are centralized** in CollisionManager; reading `.width/.height` per
   bullet per frame is too slow on native — cache radii like `collisionRadius`.
7. New display objects in the playfield go in `Main.world`; new UI goes on `Main`.
   Respect z-order: background → world (enemies → items → player → bullets) → HUD →
   boss bar → dialogue → bomb flash → FPS.
8. DEACTIVATE auto-pauses mid-run (Source/Main.hx:320) — new scenes/screens must not
   fight this.
9. Content changes: edit `tools/src/*.js`, recompile — never hand-edit generated
   `Assets/levels/level*.json`. Showcase JSONs (`showcase_*.json`) are hand-written
   engine demos; keep them valid (the validator checks them too).

---

## 3. Target asset layout (create as phases need them; keep names exactly)

```
Assets/
  art/
    characters/<charId>/
      player.png          # in-game sheet: idle/left/right strips (see Phase 2)
      portraits/<expression>.png   # dialogue/cut-in art: neutral, happy, angry, ...
      select.png          # large character-select art
    enemies/<setName>.png # fairy/etc sheets
    bullets/<family>.png  # bullet sheets (rect-addressed via sprites.json)
    backgrounds/<stageN>/ # parallax layers: far.png, mid.png, near.png, ...
    ui/                   # logo, menu frames, spell banner, etc.
  bgm/  st01.ogg, st01_boss.ogg, title.ogg, ...   (+ bgm.json manifest: titles,
        composers, loop points, music-room comments)
  sfx/  shoot.wav, enemy_die.wav, spell_declare.wav, graze.wav, extend.wav, ...
  characters.json         # CharacterDef manifest (Phase 2)
  backgrounds.json        # per-stage layer manifest (Phase 5, read by StageBackground)
  sprites.json            # existing skin manifest — extended, stays the single source
                          # of truth for enemy/bullet art resolution
```

project.xml already ships everything under `Assets/` except levels/patterns, so new
dirs need **no** project.xml edits (verify the html5 `ManifestResources` picks them up
on first build). Audio should be added with explicit type: `<assets path="Assets/bgm"
rename="assets/bgm" type="music" />` (streaming) and `<assets path="Assets/sfx"
rename="assets/sfx" type="sound" />`.

---

## 4. Phase 0 — Screen system + animated sprite substrate (do this first)

Everything later (menus, character select, spell cut-ins, animated players/enemies)
needs two foundations that don't exist yet.

### 0a. Screen/scene framework
Today the "title screen" is text in a message panel over the live playfield
(Source/Main.hx:565, 689-791: `titleText`, `optionsText`, giant `keyDown` switch).
A Touhou home screen (full-screen art, its own BGM, menu stack) can't live there.

Tasks:
- New `Source/UI/Screen.hx` interface: `enter()`, `exit()`, `update()` (called from
  Main.everyFrame), `keyDown(code):Bool`, `keyUp(code)`. New `ScreenManager` (can be
  part of Main) holding a stack (push/pop for submenus).
- Extract the *run* (everything currently gated on `currentGameState == Playing`) into
  `Source/Game/GameScreen.hx`. Keep `Main.world`, `Main.gamePaused`, `Main.fieldWidth`
  as statics — dozens of classes read them; Main stays the facade.
- Screens to create over Phases 6: `TitleScreen`, `CharacterSelectScreen`,
  `DifficultyScreen`, `PracticeScreen`, `ScoreScreen`, `MusicRoomScreen`,
  `OptionsScreen` (port the existing options rows from Source/Main.hx:409-494),
  `GameScreen`, plus the in-run pause overlay staying as-is.
- Migration order that keeps the game shippable at every commit: introduce
  Screen + ScreenManager → wrap current behavior as two screens (`LegacyTitleScreen`
  reusing the message panel, `GameScreen`) → then replace LegacyTitleScreen in Phase 6.
- Keyboard model: reuse the existing raw keyCode handling; add a tiny `MenuList` helper
  (vertical list, wrap-around, Z=confirm X=back arrows=move — Touhou controls) used by
  every menu screen so navigation feels identical everywhere.

Acceptance: game plays exactly as before; ESC pause, options, F11, DEACTIVATE
auto-pause, practice, god-mode `6969` all still work; both builds green.

### 0b. Animated sprite support in SpriteLibrary
`SpriteDef` today = `{source, rect?, scale?}` → one static frame.

Tasks:
- Extend `SpriteDef` (Source/Manager/SpriteLibrary.hx:16) with optional animation:
  `{source, rect?, scale?, frames?: Int, fps?: Float, frameW?: Int, frameH?: Int,
  mode?: "loop"|"once"|"pingpong"}` — frames laid out left-to-right from `rect` (or
  the whole image). `resolve()` returns frame list (pre-cut BitmapData array, cached).
- New `Source/UI/AnimatedBitmap.hx` (Sprite subclass): holds frames, advances on an
  `advance()` call (NOT its own ENTER_FRAME — callers drive it so pause Just Works;
  bullets advance from CollisionManager, enemies from EnemyManager.update, UI from its
  screen's update).
- Wire into `Enemy` construction and `BulletEnemy` construction behind "if frames > 1,
  use AnimatedBitmap, else the current single Bitmap" so existing art keeps its exact
  code path.
- Validator/DSL untouched (sprites.json isn't validated by tools/bh — consider adding a
  `--check` pass for it in tools/bh/validate.js while here: unknown fields, missing
  files).

Acceptance: an entry in sprites.json with `frames: 4, fps: 8` visibly animates on an
enemy and a bullet; static skins unchanged; native perf holds 60fps in stage 4
(FPS counter top-left is the readout).

---

## 5. Phase 1 — Bullet visual system (directional sprites, families, effects)

Touhou reads because bullets are legible sprites with orientation. Currently every
bullet spins cosmetically (Source/Bullet/BulletEnemy.hx:292) regardless of travel.

Tasks:
- **Facing modes**: add `facing?: "spin"|"velocity"|"player"|"fixed"` and
  `angleOffset?: Float` to the bullet SpriteDef. In `BulletEnemy.update()` replace the
  unconditional spin line:
  - `spin` (default, current behavior — existing content unchanged),
  - `velocity`: `rotation = direction + angleOffset` (rice/kunai/oval bullets — this is
    the "directionally oriented sprite" ask; sprites should be authored pointing right/0°),
  - `player`: face the player each frame — needs player position; add
    `public static var playerX/playerY` updated in `Player.updateMovement()` (both are
    playfield coords since Player lives in `Main.world`),
  - `fixed`: rotation 0.
- **Bullet families**: build `Assets/art/bullets/` sheets and register the standard
  Touhou set in sprites.json as bullet-only skins addressed by `rect`: pellet, rice,
  kunai, ofuda/card, ball S/M/L, ring, star, butterfly, knife, bubble, arrowhead.
  Naming convention `"<family>_<color>"` (e.g. `rice_red`). The engine already lets a
  spawn/pattern pick per-enemy bullet skins via the `sprite` field and `bulletSprite`
  variant plumbing — verify per-*fire* skin switching exists in the shot DSL; if not,
  add an `S.sprite("rice_red")` property command (CommandRegistry + PropertyCommands +
  DSL + validator) that sets the prototype's bullet skin for subsequent Fires.
- **Spawn flash**: optional 6–10 frame additive "materialize" effect at bullet spawn
  (Touhou bullets pop in). Cheapest: scale-down + alpha-in on the bullet itself during
  its first N frames in `BulletEnemy.update()` — no extra display objects. Gate behind a
  skin flag `spawnFx: true`; measure native FPS in stage 4 before making it default.
- **Cancel effect**: when bullets are cleared (bomb, phase end —
  `CollisionManager.clearEnemyBullets`), spawn a brief fading star/spark per bullet
  (cap at ~200 concurrent; reuse a pooled particle layer in `Main.world`). Touhou
  converts cancelled bullets to point sparks — hook score later (Phase 4 bonus).
- Hitbox note: directional long bullets (rice, kunai) keep circle collision with radius
  from the *narrow* dimension (`Math.min(w,h)/2`, currently `Math.max` at
  Source/Bullet/BulletEnemy.hx:86) — generous-to-player is correct genre behavior.
  Make radius policy a SpriteDef field `hitScale?: Float` if patterns need tuning.

Acceptance: a showcase level (`tools/src/` + compile) firing rice bullets that visibly
point along their travel direction while curving, and a ring of "player"-facing
arrowheads; bombs produce cancel sparks; 60 fps holds on native under level-4 load.

---

## 6. Phase 2 — Lasers

New projectile class — don't shoehorn into BulletEnemy's point-circle model.

Tasks:
- `Source/Bullet/BulletLaser.hx`: a beam anchored at the firer (or a fixed origin),
  defined by origin, angle, length (grows over `extendFrames`), width, lifetime, and
  states: **telegraph** (thin translucent line, NO collision, ~30–45f — non-negotiable
  fairness in Touhou) → **active** (full width, collides) → **shutdown** (shrink, no
  collision). Render: stretched sprite or vector-drawn glow (start vector — matches the
  current art style and needs no asset).
- Collision: point(player)-to-segment distance vs (laserWidth/2 + playerRadius) in
  `CollisionManager` — a separate laser list next to the bullet list; update+cull them
  in the same pass. `clearEnemyBullets()` must also kill/shutdown lasers (bomb rule:
  Touhou bombs usually *do* clear lasers here — decide once, document in the code).
- Aimed/rotating support: laser tracks its anchor enemy (bind-like) and a scripted
  `angularVelocity` for sweep lasers. Reuse `IShotEmitter` anchoring conventions from
  BulletEnemy's bind system (Source/Bullet/BulletEnemy.hx:104) rather than inventing a
  parallel one.
- Engine plumbing: `FireLaser` command in `Source/Shot/CommandRegistry.hx` +
  `FireCommands.hx` (params: angle, length, width, telegraphFrames, activeFrames,
  sweep). DSL: `S.laser({...})` in tools/bh/index.js; validator entry; TestShot case
  (Tests/TestShot.hx) asserting spawn/state timing.
- Grazing a laser: continuous graze every N frames while inside graze radius (Touhou
  lasers are graze fountains) — extend the graze check, keep `SCORE_PER_GRAZE`.

Acceptance: showcase with (a) a static cross of telegraphed lasers, (b) a sweeping
boss laser; player dies to active laser, survives telegraph; bomb clears them;
TestShot covers state transitions.

---

## 7. Phase 3 — Playable characters (art, animation, focus UI, select data)

Tasks:
- **CharacterDef manifest** `Assets/characters.json`:
  ```json
  {"characters": [{
     "id": "aviator", "name": "The Aviator",
     "sheet": "assets/art/characters/aviator/player.png",
     "frameW": 48, "frameH": 64, "idleFrames": 4, "leanFrames": 4, "fps": 8,
     "portraits": {"neutral": "...", "angry": "..."},
     "select": "assets/art/characters/aviator/select.png",
     "shotTypes": ["Spread", "Homing"],
     "speed": {"normal": 5.2, "focused": 2.2},
     "hitboxRadius": 3, "grazeRadius": 24,
     "description": "..." }]}
  ```
  Loader `Source/Manager/CharacterLibrary.hx` modeled on SpriteLibrary (cache, warn,
  fallback to a built-in def wrapping today's `assets/Player.png` so the game runs with
  zero new art).
- **Player sprite states** (Source/Player/Player.hx): kill the cosmetic spin (line 244)
  when a character sheet is present. Standard Touhou sheet = three horizontal strips:
  idle (loop), lean-left (play-once then hold last frame), lean-right. Drive from
  movement state in `updateMovement()` (moving left → lean-left strip, etc.). Use
  AnimatedBitmap from Phase 0b. This is also where a cape/wind idle animation lives —
  it's just idle frames.
- **Focus visuals**: on `setFocused(true)` show (a) the hitbox dot — small bright
  sprite at player center, above everything (Touhou shows the true hitbox only while
  focused), (b) a slow rotating focus ring. Hitbox radius comes from CharacterDef —
  and **audit CollisionManager's player hit radius** to match it (today it derives from
  sprite size; Touhou hitboxes are tiny, ~3px, with the bigger `grazeRadius` around it).
- **Shot types per character**: keep `PlayerShotType` + `PlayerShootingPattern` as the
  engine; a character maps to (typeA, typeB) chosen at select ("Character → Type"
  two-step, like Touhou's shot A/B). Speeds move from the hardcoded
  `Main.applySpeedProfile` (Source/Main.hx:583) into CharacterDef.
- **Dialogue expressions**: extend `DialogueEntryData` (Source/Manager/LevelData.hx:16)
  with `expression?: String`; portrait resolution goes `character portrait by
  expression` with the current direct-asset-path form still working. DSL `say()` gains
  an optional expression arg; validator updated. Talking-sprite animation = optional
  2-frame mouth flap while the typewriter is running (DialogueManager.everyFrame,
  Source/UI/DialogueManager.hx:201, already ticks per frame).
- Player-side spell/bomb identity per character (visuals only for now): bomb flash
  color/shape per character; real per-character bombs are a stretch goal.

Acceptance: two selectable characters (even with placeholder art) with distinct
sheets, speeds, shot pairs; focus shows hitbox dot; dialogue shows per-expression
portraits; practice/god mode unaffected.

---

## 8. Phase 4 — Spell card presentation & scoring

The mechanics (phases, timeouts, field wipes) exist in BossEnemy/EnemyManager. This
phase is the *ceremony* — the thing that makes it read as Touhou.

Tasks:
- **Data**: extend `BossPhaseData` (Source/Manager/LevelData.hx:47) with
  `spell?: Bool` (nonspell phases get no ceremony), `bonus?: Int` (starting spell
  bonus), `cutIn?: String` (boss portrait asset). DSL `phase({spell: true, bonus:
  500000, cutIn: "..."})`; validator updated.
- **Phase-change eventing**: today Main *polls* `enemyManager.getActiveBoss()` and
  `BossHealthBar.track()` re-reads state per frame. Add explicit callbacks on
  EnemyManager, wired where `onPhaseDepleted` is handled inside `spawnBoss`
  (Source/Manager/EnemyManager.hx:106): `onBossPhaseStarted(boss, phaseIndex)`,
  `onBossPhaseEnded(boss, phaseIndex, cleared:Bool /*vs timeout*/)`,
  `onBossDefeated(boss)`. GameScreen subscribes.
- **Declaration animation** `Source/UI/SpellCardAnnounce.hx` (UI layer, above boss bar,
  below dialogue): boss cut-in portrait slides diagonally across the field (~60f,
  eased, additive-ish alpha), spell name appears large center-right then docks to a
  persistent small label (top-left area is FPS + HUD is top-right — put the docked name
  under the boss bar; today the name is inside the bar and hard to read — this replaces
  that). Field edge vignette/darken during spells. All frame-driven from GameScreen's
  update, respecting gamePaused.
- **History dots**: the "remaining spell cards" dots on the boss bar
  (Source/UI/BossHealthBar.hx) get redrawn as clear star/dot markers OUTSIDE the bar
  fill so they don't blend in (this is an explicit old complaint from roadmap.md).
- **Spell bonus**: on `onBossPhaseStarted` with `spell:true`, start bonus = `bonus`
  decaying linearly to ~10% over the timeout. Failing conditions (Touhou rules): player
  death or bomb during the phase zeroes the capture. Hooks needed: `Main.useBomb`
  (Source/Main.hx:662) and `onPlayerDeath` (Source/Main.hx:809) must notify the spell
  tracker. On cleared-in-time: award bonus, big "SPELL CARD CAPTURE!" toast + SFX; on
  timeout/failed: "capture failed" toast.
- **Spell background**: while a spell phase runs, StageBackground shows a distinct
  override look (darker palette / different layer set — see Phase 5 manifest,
  `spellTheme` entry per stage). Restore on phase end.
- **Records**: persist per-spell capture history (seen/captured counts) keyed by
  `stage/bossName/phaseName` using the DisplaySettings JSON persistence pattern
  (Source/Manager/DisplaySettings.hx:204) into `spells.json` — feeds Phase 6's spell
  practice + score screens.

Acceptance: stage-4 boss (Aurelia, 6 phases alternating nonspell/spell) shows cut-ins
and names only on spell phases, bonus counts down on the boss bar, bombing zeroes it,
capture toast fires, spells.json records results.

---

## 9. Phase 5 — Stage background art

Tasks:
- `Assets/backgrounds.json`: per stage `{layers: [{image, speed, alpha?, scale?,
  scrollX?}], spellTheme: {...}}`. Extend `StageBackground.setTheme`
  (Source/UI/StageBackground.hx:49) to build image layers (Bitmap tiles, two copies
  stacked a tile-height apart, same seamless wrap trick as the current circle layers at
  line 85) when a manifest entry exists, procedural fallback otherwise. Keep
  `update()`'s speed/wrap loop — it already does the right thing.
- Sizing: background covers the full 1920x1080 stage (it's added before `world` in
  Main.init, Source/Main.hx:175) — art should be authored 1920-wide (or tiled).
  `smoothing = true` on bitmaps; watch native perf with 3+ 1080p layers (measure; if
  needed, cap layers or pre-scale).
- Optional per-layer horizontal drift (`scrollX`) for clouds; optional additive blend
  for light shafts.
- Boss/spell override handled via Phase 4's hooks.

Acceptance: stage 1 with real (or placeholder photographic) layered art scrolling at
distinct parallax speeds, seamless wrap, correct draw order under all gameplay, theme
switch on stage 2 works, 60fps native.

---

## 10. Phase 6 — Music & SFX from files

Tasks:
- **Formats**: `.ogg` only for BGM (native cannot decode mp3 — invariant #1). SFX as
  16-bit `.wav` (tiny, decode-free) or ogg. Add the two project.xml asset blocks from
  section 3 (`type="music"` streams, `type="sound"` preloads).
- **AudioManager refactor** (Source/Manager/AudioManager.hx): keep every public
  signature (callers: Main, StageManager wiring, item/bomb/death paths). Internals:
  - `playMusic(stageNumber)` consults `Assets/bgm/bgm.json`
    (`{tracks: [{id, file, title, composer, comment, loopStart?, loopEnd?, stage?,
    boss?}]}`); falls back to the current synth riff when the file is missing, so the
    game never goes silent mid-migration.
  - Looping with loop points: `SoundChannel.addEventListener(SOUND_COMPLETE)` restarts
    at `loopStart` (seconds→ms position param of `Sound.play`). Sample-accurate gapless
    looping isn't reliable in lime; the standard workaround is authoring the ogg as
    intro+loop and playing `file_intro.ogg` then looping `file_loop.ogg` — support both
    single-file and intro/loop pairs in the manifest. `tick()` (already called per
    frame from Main.everyFrame) is where any position-watching lives.
  - Boss music: `playBossTrack(stageNumber)` triggered from Phase 4's boss-spawn hook;
    restore stage track after boss death (or roll credits into next stage).
  - Ducking (`setMusicDucked`, used by pause) and volume/mute keys must keep working on
    file-based channels (`SoundTransform` on the channel).
- **SFX set**: enemy-hit (throttled like sfxFire's 8-frame throttle), enemy-death,
  player-shot, graze (subtle!), spell declare, spell capture, extend (1up), power-max,
  menu move/confirm/cancel. Central `sfx(name)` keyed by manifest; keep per-frame
  throttles — 50 simultaneous hit sounds is a real risk with pierce shots.
- html5 check: browsers block autoplay-with-audio until first input — title screen
  starts BGM on first keypress if the context was blocked (test in Chrome).

Acceptance: title + 4 stage tracks + 1 boss track playing from ogg with clean loops on
both targets; mute/volume/duck keys work; missing-file fallback verified by deleting a
track locally; SFX audible and not clipping (synth had 0.75 headroom for a reason —
normalize files similarly).

---

## 11. Phase 7 — Title screen & full menu suite

Builds on Phase 0a's screen stack. This replaces `titleText()`/panel entirely.

Screens & flow (Touhou-standard):
```
TitleScreen ── Game Start ─→ DifficultyScreen ─→ CharacterSelectScreen ─→ GameScreen
            ├─ Practice Start ─→ Difficulty → Character → PracticeScreen (stage list
            │      with per-stage best score/clear marks; uses StageManager.startRun(i, true))
            ├─ Spell Practice ─→ list from spells.json (Phase 4) → GameScreen starting
            │      at that boss phase  [needs: EnemyManager.spawnBoss "start at phase k"
            │      + a stage loader that jumps straight to the boss wave — add
            │      `startAtPhase` to spawnBoss and a StageManager.startSpell(stage, phase)]
            ├─ Score ─→ ScoreScreen (top-10 per difficulty × character, from scores.json)
            ├─ Music Room ─→ MusicRoomScreen (bgm.json list: title/composer/comment,
            │      play on select; lock tracks until first heard in-game if desired)
            ├─ Options ─→ OptionsScreen (port existing rows: display, window size,
            │      music on/off, volume + add: SFX volume, default difficulty)
            └─ Quit (native: Sys.exit(0); hidden on html5)
```

Tasks:
- **TitleScreen**: full-stage background art (`Assets/art/ui/title_bg.png`) + logo +
  character art on the side, its own BGM (`title.ogg`), vertical MenuList with the
  entries above, subtle idle animation (background drift — can literally reuse
  StageBackground with a title theme). Keyboard: arrows/Z/X; keep F11 and the music
  keys global (they're handled before screen dispatch in Main.keyDown today — preserve
  that ordering, Source/Main.hx:689).
- **CharacterSelectScreen**: large select art per character (CharacterLibrary from
  Phase 3), left/right to switch character, then shot-type A/B pick; shows stats
  (speed bars, shot description). Writes choice into a small `RunConfig`
  {character, shotType, difficulty} consumed by GameScreen instead of Main's current
  `shotType` field.
- **ScoreScreen + persistence**: `Source/Manager/ScoreStore.hx` (DisplaySettings
  pattern, `scores.json` in applicationStorageDirectory; on html5 wrap the same JSON in
  `openfl.net.SharedObject`). Record: name-entry (arcade style, 8 chars, arrow-select
  alphabet) after game over / all-clear if top-10. Hook points: `onAllStagesCleared`
  (Source/Main.hx:681) and the game-over branch of `onPlayerDeath` (Source/Main.hx:829).
- **Run results**: after all-clear, a results screen (score, continues used, spell
  cards captured x/y, graze) before returning to title — data all exists once Phase 4
  lands + a graze counter is added (increment where `onGraze` bumps score,
  Source/Main.hx:240; display on HUD too — `HUD.setGraze`).
- **Continues** (Touhou-style): on game over offer Continue (restart current stage,
  score reset to 0 + continue count++, no name entry eligibility) / Quit. Practice mode
  skips this.
- Delete `titleText/pauseText/optionsText` panel-text UI from Main once all screens
  exist; the message panel stays for in-run banners ("Stage 2 begins") and pause.

Acceptance: boot → animated title with music → full flow into a run and back out via
Q-quit/pause; scores persist across restarts (verify file in
`applicationStorageDirectory`); practice and spell practice launch correctly; html5
build navigates the same menus.

---

## 12. Phase 8 — Content build-out & balancing (ongoing, after systems land)

- Re-skin all 4 stages with the new bullet families/backgrounds/music; author
  boss cut-ins and spell names for every phase (levels live in `tools/src/level*.js`).
- Per-difficulty pattern variants: today difficulty only scales health + bullet speed
  (GameSettings). Touhou authors *different density* per difficulty. Cheapest path
  that fits the pipeline: expose `$difficulty` (0–3) as a built-in expression variable
  in `Source/Shot/Expression.hx` + validator, so patterns can write
  `S.nway("8 + 4 * $difficulty", ...)`. Bigger alternative (per-difficulty script
  blocks in phase data) only if expressions prove insufficient.
- Balancing method (from the 2026-07 pass, keep using it): player effective DPS ~30 at
  power 4 (peak 40–60 minus dodge downtime); readable bullet speed ceiling ~14 px/f
  with telegraphs; boss phase HP ≈ intended seconds × 30; fodder 8–22 HP. Playtest via
  the screenshot loop + practice mode per stage.
- New stages 5–6 + Extra stage (unlock: 1cc any difficulty — gate via ScoreStore).

## 13. Phase 9 — Stretch goals (explicitly out of scope until asked)

- **Replays**: input-recording replays require full determinism. Blockers to audit
  first: `Math.random()` in BulletEnemy salt, StageBackground layout, `S.random`/
  Expression's RNG, ItemManager scatter — all must route through one seedable RNG
  (`Source/Manager/Rng.hx`) keyed per run. Do the RNG centralization early if replays
  are ever wanted; it's cheap now, expensive later.
- Per-character bombs with unique visuals/mechanics.
- Gamepad input (lime has GameInput; MenuList/keyDown abstraction from Phase 0a is the
  place to add it).
- Endings/staff roll art per character; PoC (point-of-collection auto-collect at top —
  item collection line already exists at 30% field height in ItemManager) refinements:
  full-power auto-collect, point value popups.
- Visual editor for patterns (roadmap.md already deprioritized this — still deferred).

---

## 14. Milestone order & rough effort

| # | Milestone | Depends on | Effort (sessions) |
|---|-----------|-----------|-------------------|
| 0a | Screen framework refactor | — | 2 |
| 0b | Animated SpriteLibrary + AnimatedBitmap | — | 1 |
| 1 | Directional bullets + families + cancel FX | 0b | 2 |
| 2 | Lasers | 1 | 2 |
| 3 | Characters (defs, sheets, focus UI, dialogue expressions) | 0b | 2–3 |
| 4 | Spell card ceremony + bonus + records | 0a | 2–3 |
| 5 | Background art pipeline | — | 1 |
| 6 | File-based BGM/SFX | — | 2 |
| 7 | Title + full menus + scores | 0a, 3, 6 | 3–4 |
| 8 | Content re-skin + balance | all | ongoing |

Phases 1/2, 5, 6 are independent of each other and of 3/4 — parallelizable.
Art/music assets are the long pole: every phase is written to run with placeholder or
absent assets (fallbacks specified above) so code never blocks on art.

**Definition of done, every phase**: all four verification commands green
(section 1), a playtest on the native exe, existing showcases/levels unbroken
(`node tools/compile.js --check` covers them), and new JSON fields known to
`tools/bh/validate.js` + documented in `tools/README.md` / `SCRIPTING.md`.
