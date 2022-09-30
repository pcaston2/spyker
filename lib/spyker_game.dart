
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:neated/connection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/particles.dart';
import 'package:flame_forge2d/forge2d_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neated/activation.dart';
import 'package:neated/genome.dart';
import 'package:neated/neuralNet.dart';
import 'package:neated/neuralNetOptions.dart';
import 'package:spyker/vertical_joystick_component.dart';
import 'spyker.dart';

class SpykerGame extends Forge2DGame with HasDraggables, KeyboardEvents {

    SpykerGame(this.context) : super(gravity: Vector2.zero());
    late List<Spyker> spykers;
    late VerticalJoystickComponent leftJoystick;
    late VerticalJoystickComponent rightJoystick;
    late CircleComponent arena;
    late Spyker follow;
    late BuildContext context;
    bool usingJoystick = false;
    bool gameOver = false;
    bool scored = false;
    final double arenaRadius = 50.0;
    double gameOverTime = 0;
    late NeuralNet net;
    late Genome genome;
    int currentGenomeIndex = 0;
    int generation = 0;
    int cycleIndex = 0;
    List<num> inputs = <num>[];
    List<num> outputs = <num>[];
    late File netFile;

    Spyker getEnemy(Spyker s) {
      if (spykers.first == s) {
        return spykers[1];
      } else {
        return spykers[0];
      }
    }


    @override
    Future<void> onLoad() async {
      var options = NeuralNetOptions();
      options.sizeOfGeneration = 20;
      final directory = await getApplicationDocumentsDirectory();
      final file = "${directory.path}/spyker.net";
      netFile = File(file);
      if (await netFile.exists()) {
        print("Loading from file");
        final contents = await netFile.readAsString();
        var json = jsonDecode(contents);
        net = NeuralNet.fromJson(json);
      } else {
        print("No file exists, starting from scratch");
        net = NeuralNet.withOptions(6,2,options);
      }
      //fittest = Genome.clone(net.fittest);
      //current = currentGenome;
      camera.speed = 1;


      final knobColor = Paint()
        ..shader = const RadialGradient(
            colors:
            [

              Colors.blueGrey,
              Colors.grey,
              Colors.blueGrey,
            ]
        ).createShader(Rect.fromCircle(center: const Offset(35,35), radius: 35));

      final backgroundColor = Paint()
        ..shader = const RadialGradient(
            colors:
            [
              Colors.black,
              Colors.black,
              Colors.grey,
            ]
        ).createShader(Rect.fromCircle(center: const Offset(54,54), radius: 54));

      leftJoystick = VerticalJoystickComponent(
        knob: CircleComponent(
          radius: 35,
          paint: knobColor,
        ),
        background: CircleComponent(
          radius: 50,
          paint: backgroundColor,
        ),
        margin: const EdgeInsets.only(left: 50, bottom: 50),
        priority: 1,
      );
      leftJoystick.positionType = PositionType.widget;

      rightJoystick = VerticalJoystickComponent(
        knob: CircleComponent(
          radius: 35,
          paint: knobColor,
        ),
        background: CircleComponent(
          radius: 50,
          paint: backgroundColor,
        ),
        margin: const EdgeInsets.only(right: 50, bottom: 50),
        priority: 1,
      );

      rightJoystick.positionType = PositionType.widget;

      add(leftJoystick);
      add(rightJoystick);

      setup();

      addContactCallback(SpykerContactCallback());



      super.onLoad();
    }

    void setup() {
      final center = Vector2.zero();
      var separation = 30.0;
      spykers = [Spyker(center + Vector2(0.0, -separation)), Spyker(center + Vector2(0.0, separation),pi)];
      follow = spykers[0];
      arena = CircleComponent(radius: arenaRadius);
      arena.center = Vector2.zero();
      add(arena);
      for(var s in spykers) {
        add(s);
      }

      bool doNextGeneration = net.currentGeneration.every((g) => g.fitness > 0);
      //print (doNextGeneration);
      if (doNextGeneration) {
        net.createNextGeneration();
        for (var g in net.currentGeneration) {
          g.fitness = 0;
        }
      }
      //print(net.currentGeneration.where((g) => g.fitness == 0).length);
      genome = net.currentGeneration.firstWhere((g) => g.fitness == 0);

      netFile.writeAsString(jsonEncode(net.toJson()), flush: true);

      camera.followComponent(follow.positionComponent!);
      camera.zoom = 6.0;
      addContactCallback(SpykerContactCallback());
    }

    void reset() {

      for (var s in spykers) {
        if (s.status != SpykerStatus.dead) {
          remove(s);
        }
      }
      remove(arena);

      genome.fitness = spykers[1].score;

      gameOver = false;
      scored = false;
      gameOverTime = 0;

      spykers.clear();
      //advanceGenome();
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

    List<num> loadNetwork(Genome g, Spyker s) {
      var inputs = List<num>.empty(growable: true);
      inputs.add(s.angleToCenter);
      inputs.add(s.angleToEnemy);
      inputs.add(s.angleFromEnemy);
      inputs.add(s.distanceToEdge);
      inputs.add(s.distanceToEnemy);
      inputs.add(s.heat);
      g.registerInputs(inputs);
      return inputs;
    }

    List<num> advanceNetwork(Genome g, Spyker s) {
      g.update();
      var outputs = g.getOutputs();
      s.leftPower = outputs[0].toDouble();
      s.rightPower = outputs[1].toDouble();
      cycleIndex++;
      if (cycleIndex == 100) {
        //print("Inputs: $inputs");
        //print("Outputs: $outputs");
        cycleIndex = 0;
      }
      return outputs;
    }

    @override
    Future<void> update(double dt) async {
      // var v = Vector2(3,4);
      // var u = Vector2(5,-12);
      // var dot = u.dot(v);
      // var mag = u.length2;
      // var scale = dot / mag;
      // var u1 = u.clone();
      // u1.scale(scale);

      //load info for neural network
      if (!gameOver) {
        for (var s in spykers) {
          s.angleToCenter = s.impulseDirection().angleToSigned(-s.body.position) / pi;
          var enemy = getEnemy(s);
          var vectorToEnemy = -(s.body.position - enemy.body.position);
          s.angleToEnemy = s.impulseDirection().angleToSigned(vectorToEnemy) / pi;
          s.distanceToEnemy = Activation.gaussian(vectorToEnemy.length / 10.0).toDouble().clamp(0,1);
          s.angleFromEnemy = enemy.impulseDirection().angleToSigned(-vectorToEnemy) / pi;
          s.distanceToEdge = Activation.gaussian((arena.radius - s.body.position.length) / 5.0).toDouble().clamp(0,1);

        }
      }


      inputs = loadNetwork(genome, spykers[1]);
      outputs = advanceNetwork(genome, spykers[1]);









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
            0.2 * dt;
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

      if (!gameOver) {
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
                            radius: 0.2 * (1 - scale) + 0.05),
                        position: pos,
                      )
                  )
              );
            }
            remove(s);
            gameOver = true;
          }
        }
      }
      if (gameOver) {
        if (!scored) {
          var alive = spykers.where((s) => s.status == SpykerStatus.alive);
          var dead = spykers.where((s) => s.status == SpykerStatus.dead);
          if (alive.isEmpty) {
            for (var s in spykers) {
              s.score = 0.4;
            }
          } else {
            var timeRemaining = arena.radius / arenaRadius;
            alive.single.score = 0.5 + timeRemaining * 0.5 + (alive.single.spiked ? 0.25 : 0);
            dead.single.score = 0.5 - timeRemaining * 0.5;
          }
          scored = true;
        }
        gameOverTime += dt;
        if (gameOverTime > 3.0) {
          paused = true;
          double initialRating = (spykers[1].score * 10).clamp(0.5,10).round()/2;
          var starRating = await showDialog<double>(
              barrierDismissible: false,
              barrierColor: Colors.black26,
              context: context,
              builder: (BuildContext context) => AlertDialog(
                title: const Text('Rate your opponent'),
                content: const Text('Those with the best ratings will be promoted'),
                actions: <Widget>[
                  RatingBar.builder(
                  initialRating: initialRating,
                    minRating: 0.5,
                    direction: Axis.horizontal,
                    allowHalfRating: true,
                    itemCount: 5,
                    itemPadding: const EdgeInsets.symmetric(horizontal: 4.0),
                    itemBuilder: (context, _) => const Icon(
                      Icons.star,
                      color: Colors.amber,
                    ),
                    onRatingUpdate: (rating) {
                      Navigator.pop(context, rating);
                    },
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, 0.0),
                    child: const Text('Retry'),
                  ),
                ],
              )
          );
          spykers[1].score = starRating!;
          paused = false;
          reset();
          setup();
        }
      }


      arena.radius = max(0, arena.radius - dt);
      arena.center = Vector2.zero();

      super.update(dt);

      if (leftJoystick.direction != JoystickDirection.idle) {
        //print(leftJoystick.direction);
      }
    }

    @override
    void render(Canvas canvas) {
      super.render(canvas);
      final foreground = Paint()..color = Colors.white.withOpacity(0.75);
      final background = Paint()..color = Colors.grey.withOpacity(0.75);

      var index = 0;
      for(var val in inputs) {
        var offset = Offset(100+index*30,20);
        var radius = 10.0;
        canvas.drawCircle(offset, radius, background);
        if (index <3) {
          canvas.drawArc(Rect.fromCenter(center: offset, width: radius*2, height: radius*2), -(pi / 2) - (pi / 20) + (pi*.75) * val, pi / 10, true, foreground);
        } else {
          canvas.drawArc(Rect.fromCenter(center: offset, width: radius*2, height: radius*2), -(pi / 2) - (pi*.75), pi * 2 * .75 * val, true, foreground);
        }
        //TextSpan span = TextSpan(style: const TextStyle(color: Colors.black), text: val.toStringAsFixed(2));
        //TextPainter tp = TextPainter(text: span, textAlign: TextAlign.center, textDirection: TextDirection.ltr);
        //tp.layout();
        //tp.paint(canvas, Offset(offset.dx-13, offset.dy+4));
        index++;
      }

      index = 0;
      for(var val in outputs) {
        var offset = Offset(100+index*30,50);
        var radius = 10.0;
        canvas.drawCircle(offset, radius, background);
        canvas.drawArc(Rect.fromCenter(center: offset, width: radius*2, height: radius*2), -(pi / 2) - (pi / 20) + (pi*.75) * val, pi / 10, true, foreground);


        //TextSpan span = TextSpan(style: const TextStyle(color: Colors.black), text: val.toStringAsFixed(2));
        //TextPainter tp = TextPainter(text: span, textAlign: TextAlign.center, textDirection: TextDirection.ltr);
        //tp.layout();
        //tp.paint(canvas, Offset(offset.dx-13, offset.dy+4));
        index++;
      }

      final genomeBackground = Paint()..color = Colors.blueGrey.withOpacity(0.75);
      var offset = const Offset(10,10);
      var scale = 50.0;
        canvas.drawRect(Rect.fromLTWH(offset.dx-5, offset.dy-5, scale+10, scale+10), genomeBackground);
        for (var link in genome.connections) {
          if (!link.enabled) {
            continue;
          }
          var colorTransition = (Activation.tanh(link.weight) + 1) / 2;
          var color = Color.lerp(Colors.green, Colors.red, colorTransition);
          var connection = Paint()
            ..color = color!
            ..style = PaintingStyle.fill;
          var recurrent = Paint()
            ..color = color
            ..style = PaintingStyle.stroke;
          if (link is Loop) {
            canvas.drawCircle(
                offset + Offset(link.from.x * scale, link.from.y * scale), 6,
                recurrent);
          } else {
            canvas.drawLine(
                offset + Offset(link.from.x * scale, link.from.y * scale),
                offset + Offset(link.to.x * scale, link.to.y * scale),
                connection);
          }
        }
        for (var n in genome.nodes) {
          var colorTransition = (Activation.tanh(n.output) + 1) / 2;
          var color = Color.lerp(Colors.green, Colors.red, colorTransition);
          var node = Paint()
            ..color = color!;
          canvas.drawRect(Rect.fromCircle(
              center: offset + Offset(n.x * scale, n.y * scale), radius: 2),
              node);
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