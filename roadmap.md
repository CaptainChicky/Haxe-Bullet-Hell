**Tier 1 — Make it a playable game (each is one focused session)**
[done]
---

**Tier 2 — Content and feel (each is 1-2 sessions)**

**debug** [DONE] - Some patterns have lagging bullets. Root cause found: not a race condition but OpenFL's broadcast-event dispatch — a bullet removing its own ENTER_FRAME listener mid-dispatch made the *next* listener skip a frame. Fixed by removing all per-bullet/per-enemy listeners and updating everything centrally (bullets from CollisionManager on EXIT_FRAME, enemies + patterns from EnemyManager), preserving the legacy frame order.

**Dialogue system** [DONE] — JSON-driven `dialogue: {intro: [...], outro: [...]}` block per level, entries `{speaker, text, portrait, side}`. `DialogueManager` overlay (portrait + typewriter text box, Z/X/SPACE advances), integrated with StageManager: intro plays before waves spawn, outro after the field is cleared.

**Multiple player shot types** [DONE] — Spread / Pierce / Homing, selectable with 1/2/3 on the title screen. Hold SHIFT for focus mode: slower movement + tighter volleys (homing turns harder when focused).

**Boss fights** [DONE] — `BossEnemy` + `boss: {name, phases: [...]}` spawn block: each phase has health, a pattern (template or inline script), optional movement, and a spell card name. Phase clears wipe the field, swap patterns, grant brief invulnerability. Boss health bar UI with spell card display and remaining-phase dots. Stage 4 (level4, authored in the DSL) is the boss stage.

**Multiple enemy sprites/types** [DONE] — Data-driven `SpriteLibrary`: `sprite` on a spawn names a skin in `assets/sprites.json` (enemy art + bullet art, optional spritesheet `rect` cell and `scale` — collision radius follows). A `.png` path works as a direct drop-in with no manifest entry. `default`/`enemy2` are built in, so old content is untouched.

**sin/cos** [DONE] - offset-bound bullets orbit a ghost anchor after the owner dies so they don't freeze mid-screen; the orphan cap then force-vanishes them 60 frames (1s) after death. sincos.json previously overrode `maxOrphanFrames` to 600, which made level3's orbit chains linger for 10s after the kill — the override is removed, the 60-frame default applies, and the headless tests assert the vanish at exactly the cap. Patterns that genuinely want a long scripted drift-out can still set the `maxOrphanFrames` var.

**DSL + validator** [DONE, see "Things to keep in mind"] — `tools/` holds a zero-dependency Node toolchain: `tools/bh` (S = shot-script builders mirroring CommandRegistry, M = movement helpers `enterFrom`/`easeTo`/`weave`/..., plus `level`/`wave`/`spawn`/`boss`/`phase`/`pattern`), `tools/compile.js` (compiles `tools/src/**` to the existing JSON formats), and a static validator (unknown controls/fields, expression + `$param` checking, infinite no-Wait loops, unreachable code after blocking Concurrents, dialogue/sprite/boss shapes). `node tools/compile.js --check` also validates all hand-written JSON in Assets/. See `tools/README.md`.

---

**Tier 3 — Polish (variable effort)**

**Determine compatability** - determine if you want to keep old compatability patterns. if you decide to get rid of them, rewrite the previous levels using outdated notation into the new notation.

**Items/power system** — Enemies drop items on death (power, points, bombs, lives). Items float down, auto-collect above a Y threshold (Touhou's "collection line"). Power level affects player shot strength. Medium.

**Stage backgrounds** — Scrolling background layers. OpenFL's Tilesheet or just scrolling Bitmaps. Small-medium for basic parallax scrolling.

**Sound/music** — OpenFL has audio support. Background music per stage, sound effects for firing/dying/bombing/item pickup. Small for integration, but you need the actual audio files.

**Menu/title screen** — Title screen, difficulty select, practice mode. Medium for a proper one.

---

**Suggested order for next steps:**

2. **C++ build** — so you can actually play it standalone
3. **Lives + bombs + scoring + HUD** — turns it from a tech demo into a game
4. **Multi-level progression** — gives it structure
5. **Dialogue** — gives it story
6. **Boss fights** — gives it stakes
7. Everything else as you go

The total to get to "feels like a basic Touhou" (items 1-6) is probably 8-12 focused sessions. A full game with multiple stages, bosses, shot types, music, menus, and polish is more like 30-50 sessions — that's just the reality of game dev scope.

For the readme update, the key things to capture are: what the engine can do today (the feature list), what's broken (seeds/pods), what the firedancer inspiration is, and this roadmap. Want me to help draft that, or are you good writing it yourself?

-----

### Things ot keep in mind

* **Replace hand-authored JSON with a DSL (Python/JavaScript) that compiles to the existing JSON format.**

  * Generate verbose movement sequences (e.g., `SetVelocity`/`Wait` chains) from high-level helper functions such as `weave()`, `enterFromSide()`, and `easeTo()`.
  * Preserve the current engine and JSON parser while reducing manual authoring, enabling variables, loops, comments, and reusable templates.

* **Focus abstraction on movement scripts rather than bullet scripts.**

  * Movement paths are sampled data and are the primary source of JSON bloat.
  * Existing bullet scripting already functions as a domain-specific language (loops, concurrency, tweens) and should remain largely unchanged.

* **Implement a validation layer.**

  * Add a schema or static validator to detect invalid script structures (e.g., infinite loops inside blocking concurrent branches, malformed control flow) before runtime.
  * Reduce debugging time by catching common semantic errors during compilation.

* **Defer development of a visual editor.**

  * GUI editors are expensive to build and provide limited value for complex control-flow scripting.
  * Consider a visual timeline/editor only after the DSL and validator are complete, primarily for spawn placement and timing rather than scripting logic.

* **Evaluate existing standards (e.g., BulletML).**

  * Study established bullet-pattern scripting languages for proven semantics and vocabulary.
  * Borrow concepts where beneficial without requiring full adoption.

**Development Priority**

1. Build movement helper library and JSON compiler.
2. Add static validation/schema checking.
3. Continue authoring bullet logic through the DSL while emitting existing JSON.
4. Explore a GUI editor only if visual level layout becomes the primary bottleneck.
