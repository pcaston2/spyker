import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
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
    List<Genome> genomes = <Genome>[];
    int currentGenomeIndex = 0;
    int generation = 0;
    int cycleIndex = 0;
    List<num> inputs = <num>[];
    List<num> outputs = <num>[];
    late File netFile;
    Queue<Genome> tournament = Queue<Genome>();
    Queue<Genome> nextRound = Queue<Genome>();

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
      options.sizeOfGeneration = 16;
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
      setup();

      addContactCallback(SpykerContactCallback());


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
      );
      leftJoystick.positionType = PositionType.widget;
      add(leftJoystick);

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
      );

      rightJoystick.positionType = PositionType.widget;
      add(rightJoystick);

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

      if (tournament.isEmpty) {
        if (nextRound.length <= 1) {
          print("End of round!");
          nextRound.clear();
          net.createNextGeneration();
          netFile.writeAsString(jsonEncode(net.toJson()), flush: true);
          nextRound.addAll(net.currentGeneration);
          nextRound.forEach((g) => g.fitness = 0);
        }
        print("Next round!");
        tournament = nextRound;
        nextRound = Queue<Genome>();
        print("Tournament size: ${tournament.length}");
      }
      print("Contenders remaining: ${tournament.length}");
      genomes.clear();
      genomes.add(tournament.removeFirst());
      genomes.add(tournament.removeFirst());
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

      if (spykers.any((s) => s.score == 0)) {
        throw new Exception("Someone didn't get scored");
      }
      var winnerIndex = spykers[0].score >= spykers[1].score ? 0 : 1;
      //print("Winner Fitness: ${spykers[winnerIndex].score}");
      var winner = genomes[winnerIndex];
      winner.fitness++;
      for (int i = 0; i < 2; i++) {
        print("Genome Score #$i: ${spykers[i].score}");
        print("Fitness Score #$i: ${genomes[i].fitness}");
      }
      nextRound.add(winner);

      gameOver = false;
      scored = false;
      gameOverTime = 0;

      for (int i = 0;i<genomes.length; i++) {
        //genomes[i].fitness += spykers[i].score;
        print("Scores: ${genomes[i].fitness}");
      }
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
    void update(double dt) {
      dt *= 5;
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


      loadNetwork(genomes[0], spykers[0]);
      advanceNetwork(genomes[0], spykers[0]);

      inputs = loadNetwork(genomes[1], spykers[1]);
      outputs = advanceNetwork(genomes[1], spykers[1]);









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
            0.15 * dt;
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
    void render(Canvas c) {
      super.render(c);
      final foreground = Paint()..color = Colors.white;
      final background = Paint()..color = Colors.grey;

      var index = 0;
      for(var val in inputs) {
        var offset = Offset(50+index*60,100);
        var radius = 25.0;
        c.drawCircle(offset, radius, background);
        if (index <3) {
          c.drawArc(Rect.fromCenter(center: offset, width: radius*2, height: radius*2), -(pi / 2) - (pi / 20) + (pi*.75) * val, pi / 10, true, foreground);
        } else {
          c.drawArc(Rect.fromCenter(center: offset, width: radius*2, height: radius*2), -(pi / 2) - (pi*.75), pi * 2 * .75 * val, true, foreground);
        }
        TextSpan span = new TextSpan(style: new TextStyle(color: Colors.black), text: val.toStringAsFixed(2));
        TextPainter tp = new TextPainter(text: span, textAlign: TextAlign.center, textDirection: TextDirection.ltr);
        tp.layout();
        tp.paint(c, new Offset(offset.dx-13, offset.dy+4));
        index++;
      }

      index = 0;
      for(var val in outputs) {
        var offset = Offset(50+index*60,175);
        var radius = 25.0;
        c.drawCircle(offset, radius, background);
        c.drawArc(Rect.fromCenter(center: offset, width: radius*2, height: radius*2), -(pi / 2) - (pi / 20) + (pi*.75) * val, pi / 10, true, foreground);


        TextSpan span = new TextSpan(style: new TextStyle(color: Colors.black), text: val.toStringAsFixed(2));
        TextPainter tp = new TextPainter(text: span, textAlign: TextAlign.center, textDirection: TextDirection.ltr);
        tp.layout();
        tp.paint(c, new Offset(offset.dx-13, offset.dy+4));
        index++;
      }

      final genomeBackground = Paint()..color = Colors.blueGrey.shade50;
      var offset = Offset(50,300);
      var scale = 100.0;
      int gOffset = 0;
      for (var g in genomes) {
        c.drawRect(Rect.fromLTWH(offset.dx-20 + gOffset, offset.dy-20, scale+40, scale+40), genomeBackground);
        for (var link in g.connections) {
          if (!link.enabled) {
            continue;
          }
          var colorTransition = (Activation.tanh(link.weight) + 1) / 2;
          var color = Color.lerp(Colors.green, Colors.red, colorTransition);
          var connection = Paint()
            ..color = color!
            ..style = PaintingStyle.fill;
          if (link is Loop) {
            c.drawCircle(
                offset + Offset(link.from.x * scale + gOffset, link.from.y * scale), 6,
                connection);
          } else {
            c.drawLine(
                offset + Offset(link.from.x * scale + gOffset, link.from.y * scale),
                offset + Offset(link.to.x * scale + gOffset, link.to.y * scale),
                connection);
          }
        }
        for (var n in g.nodes) {
          var colorTransition = (Activation.tanh(n.output) + 1) / 2;
          var color = Color.lerp(Colors.green, Colors.red, colorTransition);
          var node = Paint()
            ..color = color!;
          c.drawRect(Rect.fromCircle(
              center: offset + Offset(n.x * scale + gOffset, n.y * scale), radius: 2),
              node);
        }
        gOffset = gOffset + 150;
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