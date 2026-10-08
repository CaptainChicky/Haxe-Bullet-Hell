package player;

import manager.CharacterLibrary;
import manager.CharacterLibrary.CharacterDef;
import manager.SpriteFrames;
import manager.SpriteLibrary;
import ui.AnimatedBitmap;
import openfl.events.Event;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.Assets;

enum PlayerLean {
	Idle;
	LeanLeft;
	LeanRight;
}

class Player extends Sprite {
	/** Playfield position for bullet art that faces the player (updated each frame). */
	public static var playerX:Float = 0;
	public static var playerY:Float = 0;

	private var character:CharacterDef;

	// Movement state
	private var moveUp:Bool = false;
	private var moveDown:Bool = false;
	private var moveLeft:Bool = false;
	private var moveRight:Bool = false;

	private static inline final DEFAULT_NORMAL_SPEED:Float = 5.0;
	private static inline final DEFAULT_FOCUSED_SPEED:Float = 2.2;

	private var normalSpeed:Float = DEFAULT_NORMAL_SPEED;
	private var focusedSpeed:Float = DEFAULT_FOCUSED_SPEED;
	private var moveSpeed:Float = DEFAULT_NORMAL_SPEED;
	private var hitboxRadius:Float = 3;
	private var grazeRadius:Float = 24;

	private var focused:Bool = false;

	private var stageWidth:Int;
	private var stageHeight:Int;
	private var spawnX:Float;
	private var spawnY:Float;

	private var health:Int = 1;
	private var alive:Bool = true;
	private var godMode:Bool = false;
	private var invincibleFrames:Int = 0;
	private var onDeathCallback:Void->Void;

	// Visuals
	private var bodyHolder:Sprite;
	private var staticBitmap:Bitmap;
	private var animBody:AnimatedBitmap;
	private var useSpinFallback:Bool = false;
	private var ageFrames:Int = 0;
	private var lean:PlayerLean = Idle;

	private var focusLayer:Sprite;
	private var hitboxDot:Sprite;
	private var focusRing:Sprite;
	private var focusRingAngle:Float = 0;

	public function new(stageWidth:Int, stageHeight:Int, ?characterId:String) {
		super();
		this.stageWidth = stageWidth;
		this.stageHeight = stageHeight;

		bodyHolder = new Sprite();
		addChild(bodyHolder);

		focusLayer = new Sprite();
		addChild(focusLayer);
		buildFocusGraphics();
		focusLayer.visible = false;

		applyCharacter(characterId != null ? characterId : "aviator");

		addEventListener(Event.ENTER_FRAME, everyFrame);
	}

	public function applyCharacter(characterId:String):Void {
		character = CharacterLibrary.get(characterId);
		normalSpeed = character.speed.normal;
		focusedSpeed = character.speed.focused;
		moveSpeed = focused ? focusedSpeed : normalSpeed;
		hitboxRadius = character.hitboxRadius;
		grazeRadius = character.grazeRadius;

		rebuildBodyVisual();
	}

	public function getCharacter():CharacterDef {
		return character;
	}

	public function getHitboxRadius():Float {
		return hitboxRadius;
	}

	public function getGrazeRadius():Float {
		return grazeRadius;
	}

	private function rebuildBodyVisual():Void {
		while (bodyHolder.numChildren > 0) bodyHolder.removeChildAt(0);
		staticBitmap = null;
		animBody = null;
		useSpinFallback = false;
		lean = Idle;
		var sheetPath = CharacterLibrary.resolveSheet(character);
		if (!Assets.exists(sheetPath)) {
			useSpinFallback = true;
			var bmd = Assets.getBitmapData("assets/Player.png");
			staticBitmap = new Bitmap(bmd);
			staticBitmap.x = -bmd.width / 2;
			staticBitmap.y = -bmd.height / 2;
			bodyHolder.addChild(staticBitmap);
			return;
		}

		var sheet = Assets.getBitmapData(sheetPath);
		if (!CharacterLibrary.hasAnimatedSheet(character)) {
			staticBitmap = new Bitmap(sheet);
			staticBitmap.x = -sheet.width / 2;
			staticBitmap.y = -sheet.height / 2;
			bodyHolder.addChild(staticBitmap);
			return;
		}

		var idleFrames = cutStrip(sheet, 0, character.idleFrames);
		if (idleFrames.length == 0) {
			staticBitmap = new Bitmap(sheet);
			staticBitmap.x = -sheet.width / 2;
			staticBitmap.y = -sheet.height / 2;
			bodyHolder.addChild(staticBitmap);
			return;
		}

		if (idleFrames.length == 1) {
			staticBitmap = new Bitmap(idleFrames[0]);
			staticBitmap.x = -idleFrames[0].width / 2;
			staticBitmap.y = -idleFrames[0].height / 2;
			bodyHolder.addChild(staticBitmap);
			return;
		}

		animBody = new AnimatedBitmap(idleFrames, character.fps, SpriteFrames.MODE_LOOP);
		bodyHolder.addChild(animBody);
	}

	private function cutStrip(sheet:BitmapData, strip:Int, count:Int):Array<BitmapData> {
		var def = {
			source: character.sheet,
			rect: [0.0, CharacterLibrary.stripOriginY(character, strip), character.frameW, character.frameH],
			frames: count,
			frameW: character.frameW,
			frameH: character.frameH
		};
		return SpriteLibrary.cutFrames(sheet, def);
	}

	private function buildFocusGraphics():Void {
		hitboxDot = new Sprite();
		hitboxDot.graphics.beginFill(0xffffff, 1);
		hitboxDot.graphics.drawCircle(0, 0, 2.5);
		hitboxDot.graphics.endFill();
		hitboxDot.graphics.beginFill(0x44aaff, 0.9);
		hitboxDot.graphics.drawCircle(0, 0, 1.2);
		hitboxDot.graphics.endFill();
		focusLayer.addChild(hitboxDot);

		focusRing = new Sprite();
		var r = 14.0;
		focusRing.graphics.lineStyle(1.5, 0x88ccff, 0.85);
		focusRing.graphics.drawCircle(0, 0, r);
		focusRing.graphics.lineStyle(1, 0xffffff, 0.5);
		focusRing.graphics.drawCircle(0, 0, r - 4);
		focusLayer.addChild(focusRing);
	}

	public function setMoveUp(value:Bool):Void { moveUp = value; }
	public function setMoveDown(value:Bool):Void { moveDown = value; }
	public function setMoveLeft(value:Bool):Void { moveLeft = value; }
	public function setMoveRight(value:Bool):Void { moveRight = value; }
	public function setOnDeathCallback(callback:Void->Void):Void { onDeathCallback = callback; }

	public function setSpeedProfile(normal:Float, focusedSpd:Float):Void {
		normalSpeed = normal;
		focusedSpeed = focusedSpd;
		moveSpeed = focused ? focusedSpeed : normalSpeed;
	}

	public function setFocused(value:Bool):Void {
		focused = value;
		moveSpeed = focused ? focusedSpeed : normalSpeed;
		focusLayer.visible = focused && alive;
	}

	public function isFocused():Bool {
		return focused;
	}

	public function toggleGodMode():Void {
		godMode = !godMode;
		trace("God mode: " + (godMode ? "ENABLED" : "DISABLED"));
		this.alpha = godMode ? 0.5 : 1.0;
	}

	public function isGodMode():Bool { return godMode; }

	public function setSpawnPosition(x:Float, y:Float):Void {
		spawnX = x;
		spawnY = y;
	}

	public function respawn():Void {
		health = 1;
		alive = true;
		visible = true;
		x = spawnX;
		y = spawnY;
		moveUp = moveDown = moveLeft = moveRight = false;
		focusLayer.visible = focused;
	}

	public function setInvincible(frames:Int):Void { invincibleFrames = frames; }
	public function isInvincible():Bool { return invincibleFrames > 0; }

	public function takeDamage(damage:Int):Void {
		if (!alive || invincibleFrames > 0 || godMode) return;
		health -= damage;
		if (health <= 0) die();
	}

	public function isAlive():Bool { return alive; }

	private function die():Void {
		alive = false;
		visible = false;
		focusLayer.visible = false;
		moveUp = moveDown = moveLeft = moveRight = false;
		if (onDeathCallback != null) onDeathCallback();
	}

	public function updateMovement():Void {
		if (!alive) return;

		if (moveUp) y -= moveSpeed;
		if (moveDown) y += moveSpeed;
		if (moveLeft) x -= moveSpeed;
		if (moveRight) x += moveSpeed;

		if (y < height / 2) y = height / 2;
		if (y > stageHeight - height / 2 - 10) y = stageHeight - height / 2 - 10;
		if (x < width / 2) x = width / 2;
		if (x > stageWidth - width / 2 - 10) x = stageWidth - width / 2 - 10;

		playerX = x;
		playerY = y;

		updateLeanFromInput();
	}

	private function updateLeanFromInput():Void {
		if (animBody == null && staticBitmap != null && !useSpinFallback) return;

		var want:PlayerLean = Idle;
		if (moveLeft && !moveRight) want = LeanLeft;
		else if (moveRight && !moveLeft) want = LeanRight;

		if (want != lean) {
			lean = want;
			if (animBody != null && want != Idle) {
				showLeanStrip(want);
			} else if (animBody != null && want == Idle) {
				showIdleStrip();
			}
		}
	}

	private function showIdleStrip():Void {
		var sheet = Assets.getBitmapData(CharacterLibrary.resolveSheet(character));
		var frames = cutStrip(sheet, 0, character.idleFrames);
		if (frames.length <= 1) return;
		bodyHolder.removeChild(animBody);
		animBody = new AnimatedBitmap(frames, character.fps, SpriteFrames.MODE_LOOP);
		bodyHolder.addChild(animBody);
	}

	private function showLeanStrip(side:PlayerLean):Void {
		var strip = side == LeanLeft ? 1 : 2;
		var sheet = Assets.getBitmapData(CharacterLibrary.resolveSheet(character));
		var frames = cutStrip(sheet, strip, character.leanFrames);
		if (frames.length == 0) return;
		bodyHolder.removeChild(animBody);
		var mode = frames.length > 1 ? SpriteFrames.MODE_ONCE : SpriteFrames.MODE_ONCE;
		animBody = new AnimatedBitmap(frames, character.fps, mode);
		bodyHolder.addChild(animBody);
	}

	private function everyFrame(event:Event):Void {
		if (Main.gamePaused) return;

		if (useSpinFallback) {
			ageFrames++;
			rotation = 40.0 * ageFrames / 60.0;
		} else {
			rotation = 0;
			if (animBody != null) animBody.advance();
		}

		if (focused && alive) {
			focusRingAngle += 1.2;
			focusRing.rotation = focusRingAngle;
		}

		if (invincibleFrames > 0) {
			invincibleFrames--;
			if (invincibleFrames == 0) {
				this.alpha = godMode ? 0.5 : 1.0;
			} else {
				this.alpha = (Std.int(invincibleFrames / 4) % 2 == 0) ? 0.3 : 0.8;
			}
		}
	}
}
