import 'package:flame/game.dart';

extension Projection on Vector2 {

  Vector2 project(Vector2 v) {
    var u = this;
    var dot = u.dot(v);
    var mag = u.length2;
    var scale = dot / mag;
    var u1 = u.clone();
    u1.scale(scale);
    return u1;
  }
}