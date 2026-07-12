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
