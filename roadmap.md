**Tier 1 — Make it a playable game (each is one focused session)**
[done]
---

**Tier 2 — Content and feel (each is 1-2 sessions)**

**debug** - Some patterns have lagging bullets. For instance, the radial shot pattern sometimes has a lagging bullet in the ring. There either is a race condition or something similar tha tmight be causing this issue. 

**Dialogue system** — JSON-driven: array of `{speaker, portrait, text}` entries. A `DialogueManager` overlays character portrait + text box, advances on input, pauses gameplay. Integrate with stage progression: stage manager triggers dialogue before/after levels. Medium — the UI layout and text rendering is the bulk.

**Multiple player shot types** — Currently `PlayerShootingPattern` is one pattern. Add 2-3 types (e.g. wide spread, focused narrow, homing), selectable at game start or via item pickup. Each type is a different firing pattern in the same framework. You'd also want focused/unfocused modes (hold Shift = focused = slower movement + tighter shot). Medium.

**Boss fights** — An enemy with multiple phases: health thresholds trigger pattern changes and dialogue. The pattern system already supports this (switch to a new script at each threshold). You'd need: boss health bar UI, phase transition logic in Enemy or a BossEnemy subclass, non-spell/spell card naming display. Medium-large.

**Before imeplemeting this, please take note of the "Things ot keep in mind" section** - don't try to bruteforce write thousands of lines of json from now on. a smarter method is needed.

**Multiple enemy sprites/types** — You just added the sprite system. Expanding to more types means more art assets and maybe size/collision-radius differences. The code side is small — the art side depends on you. For now there are two variants of enemy sprites and only one player sprite, but perhaps it would be good to have a framework where a dropin or a spritesheet can be used. 

---

**Tier 3 — Polish (variable effort)**

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
