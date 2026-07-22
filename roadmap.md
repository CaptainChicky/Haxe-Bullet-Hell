**Tier 1 — Make it a playable game (each is one focused session)**
[done]
---

**Tier 2 — Content and feel (each is 1-2 sessions)**
[done]

---

**Tier 3 — Polish (variable effort)**

**DSL** - make sure DSL is perfect it allows scripting every single thing in a level and can generate/use all features

**boss fights** - the UI for the fight is subpar, fix this. the bullets the bosses shoot should be averiable in size and sprites can be swapped (make sure of this, for now just make them larger i guess). thespellcar display and remainign dots are almost impossible to see, try doing them again properly like i need to see the name (perhaps theres an animatino to introduce the spellcard after idk) and the dots properly instead of having them blend in.

**Fix esc on focus loss** - esc when on focus loss (tabbing out) does not preserve some enemies during testing (right side). esc then tabbing out/focus loss should be equivalent to the perfect esc pressing in game.

~~fullscreen should also be screenshottable with winshifts~~ — **done 2026-07-21.** Fullscreen is borderless-desktop, not exclusive; the window is deliberately 1px taller than the display so DWM keeps compositing it (see DisplaySettings.apply). Win+Shift+S works on the first press.

**Dynamic screen size support** — the display architecture is done for the common case but has known gaps. Current model: a fixed 1920x1080 logical stage, `StageScaleMode.SHOW_ALL` (aspect-preserving fit + centre), and an 1800x1080 playfield centred inside the stage via Main's `world` container. Levels are authored in playfield coordinates and never see the screen. This is the standard 2D-game approach and is what Touhou does; the pieces below extend it rather than replace it.

- *Non-16:9 monitors.* Today a 4:3 or 21:9 display gets correct centred bars — right, but it wastes screen. Option A (cheap, safe): leave it. Option B: keep the 1800x1080 playfield fixed and let the *stage* widen to the monitor ratio, so UI and background gain room while gameplay stays identical and fair. B is the better end state and the `world`/stage split already exists to support it — the work is making UI lay out against a runtime stage size instead of the constant 1920x1080. Do NOT expand the playfield itself: players on wider monitors would see bullets earlier, which is a competitive advantage.
- *Native-resolution windowed presets.* `window.display.bounds` is already read in `apply()`. Offer presets derived from the actual display (e.g. 1x/0.75x/0.5x of native) instead of the hardcoded 960x540 / 1280x720 / 1600x900, which are wrong on a 1440p or 4K panel — all three are small there.
- *HiDPI.* `openfl_dpi_aware` is enabled, so the GL back buffer tracks the real window in physical pixels; untested above 100% scaling. Verify on a 150%/200% display that text and shapes render at full crispness rather than being upscaled from a 96-DPI buffer.
- *Multi-monitor.* `apply()` uses `window.display`, so it follows whichever display the window is on, but this is untested. Check that toggling fullscreen on a secondary monitor targets that monitor and not the primary.
- *Ultra-wide / very small.* Sanity-check that SHOW_ALL still produces something playable at extremes (e.g. 32:9, or a 1280x720 laptop) — mainly that HUD text stays legible when scaled down.

**Determine compatability** - determine if you want to keep old compatability patterns. if you decide to get rid of them, rewrite the previous levels using outdated notation into the new notation.

**Items/power system** — Enemies drop items on death (power, points, bombs, lives). Items float down, auto-collect if you move above a Y threshold (Touhou's "collection line"). Power level affects player shot strength. 

**Stage backgrounds** — Scrolling background layers. OpenFL's Tilesheet or just scrolling Bitmaps. Small-medium for basic parallax scrolling.

**Sound/music** — OpenFL has audio support. Background music per stage, sound effects for firing/dying/bombing/item pickup. Small for integration, but you need the actual audio files. for now perhaps just replace it with a generated at a certain frequency (like 400, 500, 200 etc Hz) sine wave. This should be togglable on and off (as in the music, you can turn music volume ormute in the game menu). this will be replaced with actual music.

**Menu/title screen** — Title screen, difficulty select, practice mode. 

---

**Suggested order for next steps:**

2. **C++ build** — so you can actually play it standalone
3. **Lives + bombs + scoring + HUD** — turns it from a tech demo into a game
4. **Multi-level progression** — gives it structure
5. **Dialogue** — gives it story
6. **Boss fights** — gives it stakes
7. Everything else as you go

The total to get to "feels like a basic Touhou" (items 1-6) is probably 8-12 focused sessions. A full game with multiple stages, bosses, shot types, music, menus, and polish is more like 30-50 sessions — that's just the reality of game dev scope.

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
