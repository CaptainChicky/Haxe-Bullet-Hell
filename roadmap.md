**Tier 1 — Make it a playable game (each is one focused session)**
[done]
---

**Tier 2 — Content and feel (each is 1-2 sessions)**
[done]

---

**Tier 3 — Polish (variable effort)**

**DSL** - make sure DSL is perfect it allows scripting every single thing in a level and can generate/use all features

**boss fights** - the UI for the fight is subpar, fix this. the bullets the bosses shoot should be averiable in size and sprites can be swapped (make sure of this, for now just make them larger i guess). thespellcar display and remainign dots are almost impossible to see, try doing them again properly like i need to see the name (perhaps theres an animatino to introduce the spellcard after idk) and the dots properly instead of having them blend in.

**Dynamic screen size support** — the display architecture is done for the common case but has known gaps. Current model: a fixed 1920x1080 logical stage, `StageScaleMode.SHOW_ALL` (aspect-preserving fit + centre), and an 1800x1080 playfield centred inside the stage via Main's `world` container. Levels are authored in playfield coordinates and never see the screen. This is the standard 2D-game approach and is what Touhou does; the pieces below extend it rather than replace it.

- *Non-16:9 monitors.* Today a 4:3 or 21:9 display gets correct centred bars — right, but it wastes screen. Option A (cheap, safe): leave it. Option B: keep the 1800x1080 playfield fixed and let the *stage* widen to the monitor ratio, so UI and background gain room while gameplay stays identical and fair. B is the better end state and the `world`/stage split already exists to support it — the work is making UI lay out against a runtime stage size instead of the constant 1920x1080. Do NOT expand the playfield itself: players on wider monitors would see bullets earlier, which is a competitive advantage.

  Deliberately deferred rather than done alongside the preset work: `LOGICAL_W`/`LOGICAL_H` are `inline final` and read by the HUD, message panel, boss bar, dialogue, bomb flash, and background. Making them runtime values touches every one of those layouts, and none of it can be verified on the only display available here (1920x1080) — the result would be untestable churn in exchange for zero change on the machine it ships from. Do this when there is a non-16:9 display to check it against.
- ~~*Native-resolution windowed presets.*~~ — **done 2026-07-21.** `DisplaySettings.refreshWindowSizes` rebuilds the three presets from `window.display.bounds` on every `apply()`, at 55/75/100% of the largest 16:9 box that fits the display minus a fixed 96px of chrome (title bar + taskbar, which sit outside the client area). The reserve is a constant pixel count, not a percentage, because chrome *is* a constant — scaling it would waste ~180px on a 4K panel, exactly where the largest preset should gain most. Heights are snapped to multiples of 9 so the ratio stays exactly 16:9 — an approximate ratio would reintroduce the sub-pixel letterboxing the preset list exists to prevent. On 1080p this gives 960x540 / 1312x738 / 1744x981; on 4K it scales up accordingly. The hardcoded list survives only as a boot/html5 fallback. Still untested on a non-1080p panel.
- *HiDPI.* `openfl_dpi_aware` is enabled, so the GL back buffer tracks the real window in physical pixels; untested above 100% scaling. Verify on a 150%/200% display that text and shapes render at full crispness rather than being upscaled from a 96-DPI buffer.
- *Multi-monitor.* `apply()` uses `window.display`, so it follows whichever display the window is on, but this is untested. Check that toggling fullscreen on a secondary monitor targets that monitor and not the primary.
- *Ultra-wide / very small.* Sanity-check that SHOW_ALL still produces something playable at extremes (e.g. 32:9, or a 1280x720 laptop) — mainly that HUD text stays legible when scaled down.

**Menu/title screen** — Title screen, difficulty select, practice mode. 

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
