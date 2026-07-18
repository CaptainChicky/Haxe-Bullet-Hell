**Tier 1 — Make it a playable game (each is one focused session)**
[done]
---

**Tier 2 — Content and feel (each is 1-2 sessions)**

**debug** - Some patterns have lagging bullets. For instance, the radial shot pattern sometimes has a lagging bullet in the ring. There either is a race condition or something similar tha tmight be causing this issue. 

**Dialogue system** — JSON-driven: array of `{speaker, portrait, text}` entries. A `DialogueManager` overlays character portrait + text box, advances on input, pauses gameplay. Integrate with stage progression: stage manager triggers dialogue before/after levels. Medium — the UI layout and text rendering is the bulk.

**Multiple player shot types** — Currently `PlayerShootingPattern` is one pattern. Add 2-3 types (e.g. wide spread, focused narrow, homing), selectable at game start or via item pickup. Each type is a different firing pattern in the same framework. You'd also want focused/unfocused modes (hold Shift = focused = slower movement + tighter shot). Medium.

**Boss fights** — An enemy with multiple phases: health thresholds trigger pattern changes and dialogue. The pattern system already supports this (switch to a new script at each threshold). You'd need: boss health bar UI, phase transition logic in Enemy or a BossEnemy subclass, non-spell/spell card naming display. Medium-large.

**Multiple enemy sprites/types** — You just added the sprite system. Expanding to more types means more art assets and maybe size/collision-radius differences. The code side is small — the art side depends on you.

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