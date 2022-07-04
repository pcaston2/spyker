import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/particles.dart';
import 'package:flame_forge2d/forge2d_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spyker/vertical_joystick_component.dart';
import 'spyker.dart';

class CircleStressSample extends Forge2DGame with HasDraggables, KeyboardEvents {

    CircleStressSample() : super(gravity: Vector2.zero());
    late List<Spyker> spykers;
    late VerticalJoystickComponent leftJoystick;
    late VerticalJoystickComponent rightJoystick;
    late CircleComponent arena;
    late Spyker follow;
    bool usingJoystick = false;


    @override
    @mustCallSuper
    void render(Canvas canvas) {
      //var paint = new Paint()..color = Colors.white;

      //canvas.drawLine(Offset.zero, Offset(friendly.body.position.x,-friendly.body.position.y), new Paint()..color = Colors.white);
      //canvas.drawLine(Offset.zero, Offset(0, -10.0), new Paint()..color = Colors.red);
      //canvas.drawCircle(Offset.zero, arenaRadius, paint);
      super.render(canvas);
    }

    @override
    Future<void> onLoad() async {




      //final boundaries = createBoundaries(this);
      //boundaries.forEach(add);
      final center = Vector2.zero(); //camera.viewport.effectiveSize / 2);

      spykers = [Spyker(center + Vector2(0.0, -10.0)), Spyker(center + Vector2(0.0, 10.0))];
      follow = spykers[0];
      arena = CircleComponent(radius: 50.0);
      arena.center = Vector2.zero();
      add(arena);
      for(var s in spykers) {
        add(s);
      }
      camera.speed = 1;
      camera.followComponent(follow.positionComponent!);

      addContactCallback(SpykerContactCallback());


      final knobColor = Paint()
        ..shader = const RadialGradient(
            colors:
            [

              Colors.blueGrey,
              Colors.grey,
              Colors.blueGrey,
            ]
        ).createShader(Rect.fromCircle(center: const Offset(20,20), radius: 20));

      final backgroundColor = Paint()
        ..shader = const RadialGradient(
            colors:
            [
              Colors.black,
              Colors.black,
              Colors.grey,
            ]
        ).createShader(Rect.fromCircle(center: const Offset(30,30), radius: 25));

      leftJoystick = VerticalJoystickComponent(
        knob: CircleComponent(
          radius: 20,
          paint: knobColor,
        ),
        background: CircleComponent(
          radius: 30,
          paint: backgroundColor,
        ),
        margin: const EdgeInsets.only(left: 50, bottom: 50),
      );
      leftJoystick.positionType = PositionType.widget;
      add(leftJoystick);

      rightJoystick = VerticalJoystickComponent(
        knob: CircleComponent(
          radius: 20,
          paint: knobColor,
        ),
        background: CircleComponent(
          radius: 30,
          paint: backgroundColor,
        ),
        margin: const EdgeInsets.only(right: 50, bottom: 50),
      );

      rightJoystick.positionType = PositionType.widget;
      add(rightJoystick);

      super.onLoad();
    }

    // void onTapDown(TapDownInfo details) {
    //   //super.onTapDown(details);
    //   final tapPosition = details.eventPosition.game;
    //   final random = Random();
    //   List.generate(15, (i) {
    //     final randomVector = (Vector2.random() - Vector2.all(-0.5)).normalized();
    //     add(Spyker(tapPosition + randomVector));
    //   });
    // }

    @override
    void update(double dt) {
      // var v = Vector2(3,4);
      // var u = Vector2(5,-12);
      // var dot = u.dot(v);
      // var mag = u.length2;
      // var scale = dot / mag;
      // var u1 = u.clone();
      // u1.scale(scale);

      //get joystick inputs

      var leftDelta = leftJoystick.delta.y * (1/leftJoystick.knobRadius).clamp(-1,1);
      var rightDelta = rightJoystick.delta.y * (1/rightJoystick.knobRadius).clamp(-1,1);

      double left = -leftDelta;
      double right = -rightDelta;

      if (usingJoystick) {
        follow.leftPower = left;
      }
      if (usingJoystick) {
        follow.rightPower = right;
      }

      if (leftJoystick.direction != JoystickDirection.idle || rightJoystick.direction != JoystickDirection.idle) {
        usingJoystick = true;
      } else {
        usingJoystick = false;
      }

      // var particlePaint = Paint()
      //   ..shader = const RadialGradient(
      //     colors: [
      //       Colors.green,
      //       Colors.yellow,
      //       Colors.red,
      //     ],
      //     radius: 0.50,
      //   ).createShader(Rect.fromCircle(center: Offset.zero, radius: 0.20));


      final paint = Paint()..color = Colors.orange;
      for (var s in spykers.where((x) => x.status == SpykerStatus.alive)) {
        if (s.hasCollided) {
          s.hasCollided = false;
          if (s == follow) {
            //camera.shake();
          }
          for (int i = 0; i < 5; i++) {
            var pos = Vector2.copy(s.collisionPosition);
            var dir = Vector2.copy(s.collisionVelocity);
            dir.rotate(Random().nextDouble() * 0.2 - 0.1);
            dir.scale(Random().nextDouble() * 0.3 + 0.7);
            pos.y *= -1;
            add(
                ParticleSystemComponent(
                    particle: AcceleratedParticle(
                      speed: dir,
                      lifespan: 0.5,
                      child: CircleParticle(paint: paint,
                          radius: 0.05 * Random().nextDouble() + 0.05),
                      position: pos,
                    )
                )
            );
          }
        }

      // for (var i =0; i<2;i++) {
      //   var vector = Vector2(0,5)..rotate(Random().nextDouble()*pi*2)..scale(Random().nextDouble()+0.1);
      //   add(
      //     // Wrapping a Particle with ParticleComponent
      //     // which maps Component lifecycle hooks to Particle ones
      //     // and embeds a trigger for removing the component.
      //     ParticleSystemComponent(
      //       particle: AcceleratedParticle(
      //         speed: vector,
      //         lifespan: 1,
      //         child: CircleParticle(paint: paint, radius: 0.1*Random().nextDouble()+0.1),
      //       ),
      //     ),
      //   );
      // }


      //double turn = -delta.x;
        var heating = (s.leftPower.abs() + s.rightPower.abs()) *
            0.002;
        var cooling = 1 - heating;
        s.heat += heating;
        s.heat -= cooling * 0.0015;
        s.heat = s.heat.clamp(0, 1);
        if (s == follow) {
          if (s.heat > 0.65) {
            camera.shake(duration: dt, intensity: s.heat * 0.05);
          }
        }
        if (s.heat == 1.0) {
          s.status = SpykerStatus.died;
        }
        s.body.applyForce(
            s.impulseDirection() * s.leftPower * 30,
            point: s.leftWheel());
        s.body.applyForce(
            s.impulseDirection() * s.rightPower * 30,
            point: s.rightWheel());
        //friendly.body.applyAngularImpulse(turn * dt * 15);
        //friendly.body.applyForce(friendly.impulseDirection() * dt * left * 100);//, point: friendly.leftWheel());
        //friendly.body.applyForce(friendly.impulseDirection() * forward * 40);//friendly.impulseDirection() * dt * forward * 100);//, point: friendly.rightWheel());

        //friendly.body.applyForce(-friendly.body.linearVelocity * dt);
        //print(friendly.impulseDirection());

        //var v = friendly.body.linearVelocity;
        //var u = friendly.impulseDirection();
        //print(u);
        //if (!v.isZero()) {
          //var friction = v.project(u);
          //print(u.dot(friction));
          //friction.scale(-1);
          //friendly.body.applyForce(friction);
        //}


        if (!arena.containsPoint(s.body.position)) {
          s.status = SpykerStatus.died;
        }

      }

      for (var s in spykers) {
        if (s.status == SpykerStatus.died) {
          s.status = SpykerStatus.dead;
          for (int i = 0; i < 50; i++) {
            var pos = Vector2.copy(s.body.position);
            var dir = Vector2(0, 10);
            dir.rotate(pi * 2 * Random().nextDouble());
            var scale = Random().nextDouble() * 0.8 + 0.2;
            dir.scale(scale);
            pos.y *= -1;
            add(
                ParticleSystemComponent(
                    particle: AcceleratedParticle(
                      speed: dir,
                      lifespan: 1.5,
                      child: CircleParticle(paint: paint,
                          radius: 0.2 * (1-scale) + 0.05),
                      position: pos,
                    )
                )
            );
          }
          remove(s);
        }
      }


      //arena.radius -= dt;
      //arena.center = Vector2.zero();

      super.update(dt);

      if (leftJoystick.direction != JoystickDirection.idle) {
        //print(leftJoystick.direction);
      }
    }

    @override
    KeyEventResult onKeyEvent(
        RawKeyEvent event,
        Set<LogicalKeyboardKey> keysPressed,
        ) {
      final isKeyDown = event is RawKeyDownEvent;

        if (keysPressed.contains(LogicalKeyboardKey.keyA)) {
          if (isKeyDown) {
            follow.leftPower = 1;
          }
        } else if (keysPressed.contains(LogicalKeyboardKey.keyZ)) {
          if (isKeyDown) {
            follow.leftPower = -1;
          }
        } else {
          follow.leftPower = 0;
        }
        if (keysPressed.contains(LogicalKeyboardKey.keyK)) {
          if (isKeyDown) {
            follow.rightPower = 1;
          }
        } else if (keysPressed.contains(LogicalKeyboardKey.keyM)) {
          if (isKeyDown) {
            follow.rightPower = -1;
          }
        } else {
          follow.rightPower = 0;
        }

        return KeyEventResult.handled;
      }
}