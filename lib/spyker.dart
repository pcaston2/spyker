import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_forge2d/contact_callbacks.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flame_forge2d/position_body_component.dart';
import 'package:flutter/material.dart';

enum SpykerStatus {
  alive,
  died,
  dead
}

class Spyker extends PositionBodyComponent {
  late Paint originalPaint;
  final Vector2 _position;
  late Fixture spikeFixture;
  late Fixture powerFixture;
  bool hasCollided = false;
  Vector2 collisionPosition = Vector2.zero();
  Vector2 collisionVelocity = Vector2.zero();
  SpykerStatus status = SpykerStatus.alive;
  double heat = 0;
  double lp = 0;
  double rp = 0;

  double get leftPower {
    return lp;
  }

  set leftPower(double newPower) {
    lp = newPower.clamp(-1,1);
  }

  double get rightPower {
    return rp;
  }

  set rightPower(double newPower) {
    rp = newPower.clamp(-1,1);
  }

  bool isSpike(Fixture f) {
    return f == spikeFixture;
  }

  bool isPower(Fixture f) {
    return f == powerFixture;
  }

  bool isCollidable(Fixture f) {
    return isSpike(f) || isPower(f);
  }

  Vector2 leftWheel() {
    var wheel = Vector2(-0.75, 0);
    wheel.rotate(body.angle);
    wheel += body.position;
    return wheel;
  }

  Vector2 rightWheel() {
    var wheel = Vector2(0.75, 0);
    wheel.rotate(body.angle);
    wheel += body.position;
    return wheel;
  }

  Vector2 impulseDirection() {
    var impulse = Vector2(0,1);
    impulse.rotate(body.angle);
    return impulse;
  }

  Spyker(this._position) : super(size:Vector2(0,1)) {
    debugMode = true;
    positionComponent = PositionComponent();
    //positionComponent!.changeParent(this);
    originalPaint = //BasicPalette.red.paint();
    Paint()
      ..shader = const LinearGradient(
          colors:
          [
            Colors.blue,
            Colors.red,
            Colors.red,
            Colors.grey,
          ],
          stops:
          [
            0.04,
            0.04,
            0.96,
            0.96,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
      ).createShader(Rect.fromCenter(center: Offset.zero, width: 10, height: 2));
    paint = originalPaint;
  }

  @override
  Body createBody() {
    final bodyDef = BodyDef()
    // To be able to determine object in collision
      ..userData = this
      ..angularDamping = 3
      ..linearDamping = 0.95
      ..position = _position
      ..type = BodyType.dynamic;

    var body = world.createBody(bodyDef);

    final spikeShape = PolygonShape()
      ..set(
        [
          Vector2( 0.00, 1.75),
          Vector2( 0.75, 0.75),
          Vector2(-0.75, 0.75),
        ]
      );

    var spikeFixtureDef = FixtureDef(spikeShape)
      ..restitution = 0.95
      ..density = 1.0
      ..friction = 0.1;

    spikeFixture = body.createFixture(spikeFixtureDef);

    final bodyShape = PolygonShape()
      ..set(
        [
          Vector2( 1.0, 1.0),
          Vector2( 1.0,-1.0),
          Vector2(-1.0,-1.0),
          Vector2(-1.0, 1.0),
        ]
      );

    final bodyFixtureDef = FixtureDef(bodyShape)
      ..restitution = 0.8
      ..density = 1.0
      ..friction = 0.8;

    body.createFixture(bodyFixtureDef);

    final powerShape = PolygonShape()
      ..set(
        [
          Vector2( 0.75,-0.75),
          Vector2( 0.50,-1.50),
          Vector2( 0.00,-1.66),
          Vector2(-0.50,-1.50),
          Vector2(-0.75,-0.75),
        ]
      );

    var powerFixtureDef = FixtureDef(powerShape)
      ..restitution = 0.95
      ..density = 1.00
      ..friction = 0.1;
    
    powerFixture = body.createFixture(powerFixtureDef);

    return body;
  }

  @override
  @mustCallSuper
  void render(Canvas canvas) {
    //canvas.rotate(-body.angle);
    // canvas.renderRotated(body.angle, this.position, (c) {
    //     c.drawLine(Offset.zero, Offset(impulseDirection().x*10.0,impulseDirection().y*10.0), new Paint()..color = Colors.white);
    //   }
    // );
    //canvas.drawLine(Offset.zero, Offset(impulseDirection().x*10.0,impulseDirection().y*10.0), new Paint()..color = Colors.white);
    //canvas.drawLine(Offset.zero, Offset(0, -10.0), new Paint()..color = Colors.red);

    super.render(canvas);
    var heatBrushRect = const Rect.fromLTRB(-1.5, 2.3, 1.5, 1.9);
    var heatPaint = Paint()
      ..shader = const RadialGradient(
        colors: [
          Colors.green,
          Colors.yellow,
          Colors.red,
        ],
        radius: 3.5,
      ).createShader(heatBrushRect);
    var heatRect = Rect.fromLTRB(-0.2-1.3*heat, 2.3,  0.2+1.3*heat, 1.9);
    canvas.drawRect(heatRect, heatPaint);

  }
}


class SpykerContactCallback extends ContactCallback<Spyker, Spyker> {
  @override
  void begin(Spyker a, Spyker b, Contact contact) {
    final worldContact = WorldManifold();
    contact.getWorldManifold(worldContact);
    // print('Local points: ${contact.manifold.localPoint}');
    // print('World points: ${worldContact.points}');
    final av = a.body.linearVelocityFromWorldPoint(worldContact.points[0]);
    final bv = b.body.linearVelocityFromWorldPoint(worldContact.points[0]);

    a.hasCollided = true;
    a.collisionPosition = worldContact.points[0];
    //a.collisionPosition.y = 0;//-a.collisionPosition.y;
    b.collisionPosition = worldContact.points[0];
    //b.collisionPosition.y = 0;//-b.collisionPosition.y;
    a.collisionVelocity = av - bv;
    b.collisionVelocity = bv - av;
    b.hasCollided = true;

    if (a.isCollidable(contact.fixtureA) && b.isCollidable(contact.fixtureB)) {
      if (a.isSpike(contact.fixtureA) && b.isPower(contact.fixtureB)) {
        b.status = SpykerStatus.died;
      } else if (b.isSpike(contact.fixtureB) && a.isPower(contact.fixtureA)) {
        a.status = SpykerStatus.died;
      }
    }
  }

  @override
  void end(Spyker a, Spyker b, Contact contact) {
    // TODO: implement end
  }
}


// class SpykerWallContactCallback extends ContactCallback<Spyker, Wall> {
//   @override
//   void begin(Spyker a, Wall b, Contact contact) {
//     b.paint = a.paint;
//   }
//
//   @override
//   void end(Spyker a, Wall b, Contact contact) {
//     // TODO: implement end
//   }
// }