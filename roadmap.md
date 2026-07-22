**Tier 1 — Make it a playable game (each is one focused session)**
[done]
---

**Tier 2 — Content and feel (each is 1-2 sessions)**
[done]

---

**Tier 3 — Polish (variable effort)**

**DSL** - make sure DSL is perfect it allows scripting every single thing in a level and can generate/use all features

**boss fights** - the UI for the fight is subpar, fix this. the bullets the bosses shoot should be averiable in size and sprites can be swapped (make sure of this, for now just make them larger i guess). thespellcar display and remainign dots are almost impossible to see, try doing them again properly like i need to see the name (perhaps theres an animatino to introduce the spellcard after idk) and the dots properly instead of having them blend in.

hexagram isn't done properly. should have moving bullets like static geo ish not spinning bullets, like they should be spawning and then moving ig?

the mannji arms shoudl extend longer to make a perfect square. the lasers also seem slightly broken, as from what i can tell 3 of them shoot but the 4th one doesn't? check this ig.

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
