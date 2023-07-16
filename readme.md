# Haxe-Bullet-Hell
🤔 wacky start to a bullet hell attempt with openfl. Probably not the best idea and should've used haxeflixel, but sunk cost fallacy hits different sometimes. Plus, good coding practice ig.

I probably will not finish this anytime soon. If anyone wants to help, feel free to create a pull request/issue :)

# How to run
Compile into html5 using `openfl build html5 -release -clean` or `openfl test html5`.

# To-Do
1. Make a class "EnemyShootingLevel" or something which encapsulates enemy patterns into a level.
2. Implement health system.
3. Implement point system. The higher the player's points, the better the payer shooting pattern.
4. Encapsulate player speed controls and movement into the player class perhaps(?)
5. Implement enemy movement and targetting. Currently, I'm just spawning an enemy on the canvas in the main class.
6. Implement enemy spawning and spawning patterns.

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

enemyshootingpattern is an abstract class that has a patternstarttime as the current global time, an isShooting, a bulletSpawnTimer, and bulletSpawnInterval that you set manually.

start and shopshooting are the same as player, and setBulletSpawnInterval sets the bullet spawn interval.

everyframe gets the time between each frame, and increments bulletSpawnTimer. If isShooting and bulletspanwtimer exceeds or equals bulletspawninterval, then we spawnenemybullet and reset the spawn timer.

we have an abstract function spawnenemybullet.

Currently, two custum patterns exist. Spiral and nwhip. 

Spiral has a bulletSpeed, rotationChange, and currentRotation. It spawns a bullet by first setting the bullet's location to the enemy bullet. Then, the velocity is calculated by by taking the sin or cos of currentRotation (rotational startign position, usually 0), and multiplies this by bulletSpeed. set this as the bullet's velocity and spawn it. We then increment currentRotation by rotationChange for the next bullet.

Works best with bulletspawninterval being 0.01 s or 1ms. *Here's something to note. If you stare at the screen with the enemy in the dead center, 0 deg is left of the enemy. 90 is down. 180 is right. 270 is up. This means in the current player enemy setup, the player is 90 degrees from the enemy's perspective.*

Nwhip has a is based on the firedancer pattern. It has a whipfullangle, numberofwhips, and numberofbullets. Less important ones are baseangle, angletofire, salt, as well as basebulletspeed, and speedchange.

On initialization, nwhip will add an everyframe event listenner, calculate the baseangle (the angle between two whips) to be the whipfullangle/numberofwhips. It then set's angletofire as 

    (90 - (numberOfBullets/2 * salt)) - (0.5 * (numberOfWhips - 1)) * baseAngle;

90 is to face downwards, subtracted by the deviation added by the salt to center the central whip angle to the exact center. Then, we start at the very left by subtracting baseAngle * (numberofwhips-1)/2. This is incremented later.

now we have the function spawnwhiprow, which spawns the first wave of bullets in the whip. For 0 to the number of whips, we spawn a bullet on the enemy, set its velocity to be cos or sin of angletofire times bulletspeed, and give it to the bullet as its velo. Then, for each sequential bullet in the numberofwhips, we increment the baseangle. This makes the entire row of all whips. We reset the angletofire for the next row.

We want the whip to contain numberOfBullet rows, and for the rows to fire after some delay instead of per frame. Hence, the spawnenemybullet has to implement a spanwNextBullet function as a manual for loop. With the currentindex as 0 until it numberOfBullets, it will call spawnNextBullet which increments by the salt times the currentindex (each whiprow should be offset by the salt from the previous). Then, it spawns the row and increments the bullet speed and index, while setting a 40ms timer before the next row is called. This is done until the index is equal to the number of bullets, which spawns the entire Nwhip.

The bulletSpawnInterval is hence then the spawn interval of each Nwhip.

# Notes
This is very noobishly written and I genuinly hope that I don't have to rewrite this because the structure is trash. I will probably make a very basic bullet hell level out of this for an internet game and move onto a more practical language to code a bullet hell game in lol (if i have enough time and motivation of course kek). Again, pull requests and issues welcome. I would certainly appreciate help lmao, if anyone even sees this.