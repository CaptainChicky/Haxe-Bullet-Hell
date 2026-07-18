# Haxe-Bullet-Hell
🤔 wacky start to a bullet hell attempt with openfl. Probably not the best idea and should've used haxeflixel, but sunk cost fallacy hits different sometimes. Plus, good coding practice ig.

I probably will not finish this anytime soon. If anyone wants to help, feel free to create a pull request/issue :)

# How to run
Compile into html5 using `openfl build html5 -release -clean` or `openfl test html5`.

For the native Windows build, use `openfl build windows -release` — the exe lands in `Export/windows/bin/BulletHell.exe` (run it from that folder; it needs `lime.ndll` and `assets/` next to it). It runs fullscreen at 60 fps with vsync. Note: `<window fps="60" />` in project.xml matters — native targets default to 30 fps and look laggy without it. Text uses the bundled Noto Sans font in `Assets/fonts/`, since system fonts like Verdana don't exist on native targets.

## Controls
- ARROW KEYS — move
- Z — shoot
- X — bomb (clears all enemy bullets, brief invincibility, 3 per life)
- SPACE — start / restart

# Architecture (UPDATED!)
The codebase has been completely refactored to be data-driven and scalable!

# issues/todo

- implement variables in bullet stuff maybe?
- bullet velocity mutation
- bind (bullet velocity follow/mutation)
- ~~point system~~ ✅ DONE! (kills = 100 × enemy max health, grazes = 10)
- ~~level switching so when you clear a level it goes to the next one after a delay~~ ✅ DONE! (StageManager runs level1 → level2 → level3)

## Game systems (Tier 1)
- **Lives**: 3 per run. Death respawns you with ~3s of invincibility (blinking) and clears the bullet field; game over at 0.
- **Bombs**: 3 per life, X key. Clears every enemy bullet, screen flash, ~2s invincibility.
- **Scoring**: enemy kill = 100 × max health, graze = 10 (each enemy bullet can graze once). HUD top-right shows score/lives/bombs; FPS counter top-left.
- **Stages**: StageManager sequences level1 → level2 → level3 with "Stage N" intros and "Stage Clear" transitions; beating stage 3 shows final score.

man this shit is hard idk how ZUN does this lmao alone

# old to-Do
1. ~~Make a class "EnemyShootingLevel" or something which encapsulates enemy patterns into a level.~~ ✅ DONE!
2. ~~Implement health system.~~ ✅ DONE!
3. Implement point system. The higher the player's points, the better the payer shooting pattern.
4. ~~Encapsulate player speed controls and movement into the player class perhaps(?)~~ ✅ DONE!
5. Implement enemy movement and targetting.
6. ~~Implement enemy spawning and spawning patterns.~~ ✅ DONE!

## New Manager System
- **EnemyManager** - Handles spawning, lifecycle, and cleanup of all enemies
- **LevelManager** - Parses JSON level files and triggers enemy spawns at the correct times
- **Player** - Now fully self-contained with its own movement, boundaries, and controls

## Creating New Levels
Levels are defined as JSON files in `Assets/levels/`. Here's the format:

```json
{
  "name": "Level Name",
  "waves": [
    {
      "startTime": 0,
      "enemies": [
        {
          "spawnTime": 0,
          "x": 400,
          "y": 100,
          "pattern": "nwhip",
          "patternConfig": {
            "bulletSpawnInterval": 1.0
          }
        }
      ]
    }
  ]
}
```

### Level Structure
- **name** - Level display name
- **waves** - Array of wave definitions
  - **startTime** - When the wave starts (seconds since level start)
  - **enemies** - Array of enemy spawns in this wave
    - **spawnTime** - When to spawn relative to wave start (seconds)
    - **x, y** - Spawn position
    - **pattern** - Pattern type: "spiral" or "nwhip"
    - **health** - Enemy health (number of player bullets to destroy, optional, defaults to 1)
    - **patternConfig** - Pattern-specific settings
      - **bulletSpawnInterval** - Time between bullet spawns (seconds)

### Example Levels
- `Assets/levels/level1.json` - Introductory level with progressive difficulty
- `Assets/levels/level2.json` - Chaotic multi-enemy patterns

### Switching Levels
In Main.hx:96, change the level file:
```haxe
levelManager.loadLevel("assets/levels/level2.json");
```

# Health System
- **Player**: Has 1 health. One enemy bullet hit = game over!
  - Hitbox: Small circular area (3px radius) centered on player sprite
  - Press SPACE to restart after death
- **Enemies**: Configurable health per enemy (set in level JSON)
  - Hitbox: Full sprite bounds
  - Requires multiple player bullets to destroy (based on health value)
  - Example: Enemy with health=5 needs 5 player bullet hits to destroy

# Dependencies
Openfl for now and lime. Check https://github.com/CaptainChicky/Haxe-Pong to install them. 

I wanted to implement firedancer (https://firedancer-lang.com/ and https://github.com/fal-works/firedancer) but this did not work out. This is because well first of all this needs a really specific version of Haxe (v4.1.3). This means I can't even implement abstract classes if i chose to use firedancer. Then, it was too complicated to use so bruh whatever. If anyone's able to help me with this that would be really nice, but for now I'll just stick to trying to implement the shooting patterns myself with openfl.

# Structure
Mainly for me to remember when I come back to this later.

## Main.hx
I set the two gamestate enums paused and playing. 

In the initialization function, the player and enemy are spawned, as well as the text. I set the gamestate to paused, add event listenners to keyup keydown and everyframe. Set the player shooting pattern/speed.

Setgamestate function makes the text dissapear and starts enemyshootsequence when gamestate is playing.

Currently I'm testing the pattern implementations in enemyshootsequence with a created spiral and nwhip pattern. Only the nwhip pattern is being fired currently.

keydown tests for movement, and sets game state to playing on space. Z shoots.  
keyup just stops what keydown does.

everyframe checks if the gamestate is playing. if it is, then sets the game boundaries for the player.

then the main generates the game.

## bullet package - BulletEnemy and BulletPlayer
This contains bullet behavior. Each bullet has a static inline final rotation speed with a magnitude of 90 per second. Enemies rotate opposite of players. Each bullet has a velocity x y, a spawntime, and a "salt" which adds randomness to the bullet's rotation.

When a bullet is created, we get the bitmap image, and set the bullet's position to the center of the sprite. We set the spawntime to the global time currently at creation and add a everyframe event listenner.

everyframe changes the bullet's position based on velocity. It then kills the bullet if its more than 100 pixels out of bounds in any direction.

Then we have a deltatime variable that gets the current time in seconds. rotation is updated by multiplying the rotation speed by the deltatime, and this overall rotation is set to start with the randomly chosen salt.

## player package - Player and PlayerShootingPattern
Player has a set rotation speed and spawntime. On spawn, we set the player to its sprite and center it. Then we have the everyframe event listenner. The player's rotation speed is based on global time.

playershootingpattern has a spawnplayerbullet function that generates the bullet. currently, it has a velocity of (x, y)=(0, -3), which shoots upwards. this is a placeholder. 

On ever frame, if isSHooting (z pressed), spawnplayerbullet. startShooting sets isShooting to true, and stopShooting sets it to false. They also respectively add and remove everyframe event listenner.

## enemy package - Enemy and EnemyShootingPattern
Enemy is built literally exactly like player except it also has a "salt" for rotation randomness and rotates in the opposite direction.

### EnemyShootingPattern (Base Class)
Abstract base class providing core functionality for all shooting patterns:
- Manages `isShooting` state and event listeners
- Provides static `CollisionManager` for bullet registration
- `startShooting()` / `stopShooting()` control the ENTER_FRAME listener
- `everyFrame()` is overridden by subclasses to implement pattern logic

### ScriptedShootingPattern (Script-Based System)
All enemy patterns now use a **data-driven script system** defined in JSON:
- Patterns are composed from actions: Fire, Wait, Loop, Rep, SetAngle, AddAngle, SetSpeed, AddSpeed, Radial, NWay
- Scripts execute frame-by-frame with precise timing control via Wait commands
- Pattern templates stored in `Assets/patterns/*.json` with configurable parameters
- Levels can reference templates or use inline scripts directly

### Pattern Templates
**spiral.json**: Fires bullets while rotating continuously
- Parameters: `bulletSpeed`, `rotationChange`, `fireDelay`

**nwhip.json**: Based on firedancer pattern with spreading bullet whips
- Parameters: `numberOfWhips`, `numberOfBullets`, `baseBulletSpeed`, `speedChange`, `fireAngle`, `angleChange`, `bulletDelay`, `patternDelay`

**radial.json**: Fires bullets in all directions
- Parameters: `bulletCount`, `bulletSpeed`, `rotationSpeed`

### Angle Convention
When enemy is at screen center: 0°=right, 90°=down, 180°=left, 270°=up
(Player positioned below enemy = 90° from enemy's perspective)

# Notes
This is very noobishly written and I genuinly hope that I don't have to rewrite this because the structure is trash. I will probably make a very basic bullet hell level out of this for an internet game and move onto a more practical language to code a bullet hell game in lol (if i have enough time and motivation of course kek). Again, pull requests and issues welcome. I would certainly appreciate help lmao, if anyone even sees this.