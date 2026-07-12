Move:
```
/*
  Terminology:
    position = { r: distance, θ: bearing }
    velocity = { r: speed,  θ: direction }

  Angle values are in degrees, north-based and clockwise.
*/

loop([
  velocity.set(8, 180), // polar coords (length, angle) at default
  wait(30),
  velocity.add(16, 0), // you can either set or add
  wait(30),
  speed.set(0), // set/add length or angle independently
  wait(30),
  fire(),
  wait(30)
]);
```
Move (2):
```
loop([
  velocity.set(16, 180).frames(60), // change gradually
  speed.set(0),
  wait(30),
  velocity.cartesian.set(0, -16), // cartesian coords
  speed.set(0).frames(60),
  wait(30),
]);
```
Fire with Pattern (Shifter):
```
[
  shot.velocity.set(5, 180),
  loop([
    fire([
      wait(30),
      direction.add(-120)
    ]),
    shot.direction.add(36),
    wait(8)
  ])
];
```
Bind Position:
```
/*
  If you call bind() after fire(),
  the position of fired actor will be
  relative from the actor that fired it.
*/

[
  shot.position.set(30, 180),
  loop([
    rep(12, [
      fire(loop([
        distance.add(4),
        bearing.add(1),
        wait(1)
      ])).bind(),
      shot.bearing.add(30),
    ]),
    wait(30)
  ])
];
```
Sin/Cos:
```
final varBearing = angleVar("bearing");

[
  shot.position.cartesian.set(270, 0),
  rep(16, [
    fire([
      varBearing.let(),
      loop([
        position.cartesian.set(
          270 * cos(varBearing),
          60 * sin(varBearing)
        ),
        wait(1),
        varBearing.add(4)
      ])
    ]).bind(),
    wait(4)
  ])
];
```
Transform:
```
final varBearing = angleVar("bearing");
final varRotation = angleVar("rotation");

[
  rep(24, [
    fire([
      varBearing.let(),
      varRotation.let(),
      loop([
        position.set(150, varBearing)
          .rotate(varRotation)
          .scale(1.0, 0.3),
        wait(1),
        varBearing.add(4),
        varRotation.add(2)
      ])
    ]).bind(),
    wait(6)
  ])
];
```
Laundry:
```
[
  shot.speed.set(12),
  parallel([
    loop([
      radial(10),
      shot.direction.add(8),
      wait(4)
    ]),
    loop([
      radial(4),
      shot.direction.add(4),
      wait(2)
    ]),
    loop([
      radial(4),
      shot.direction.add(-4),
      wait(2)
    ])
  ])
];
```
FlowerDup:
```
loop([
  shot.velocity.set(4, 180),
  shot.position.set(80, 180),
  dup(
    32,
    {
      shotBearingRange: { start: 0, end: 360 },
      shotDirectionRange: { start: 0, end: 360 }
    },
    [
      shot.direction.add(90),
      nWay(9, { angle: 90 }, fire([
        speed.set(1).frames(30),
        parallel([
          direction.add(210).frames(60),
          speed.set(2).frames(60)
        ])
      ]))
    ]
  ),
  wait(240)
])
```
Seeds:
```
// You can freely structure your code within the Haxe syntax.

final lineSeed = [
  shot.velocity.set(1, shot.angleToTarget),
  speed.set(1).frames(30),
  line(12, { shotSpeedChange: 6 }, fire([ wait(15), speed.add(5).frames(60) ])),
  vanish()
];

final nWaySeed = [
  speed.set(1).frames(30),
  shot.velocity.set(8, shot.angleToTarget),
  nWay(5, { angle: 150 }, fire(lineSeed)),
  vanish()
];

loop([
  shot.velocity.set(random.between(6, 9), 90 + random.angle.grouping(90)),
  fire(nWaySeed),
  wait(30),
  shot.velocity.set(random.between(6, 9), 270 + random.angle.grouping(90)),
  fire(nWaySeed),
  wait(30)
]);
```
