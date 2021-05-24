import 'package:flame/components.dart';
import 'package:tiled/tiled.dart';

import 'dart:ui';

import './tiled.dart';

class TiledComponent extends Component {
  Tiled tiled;

  TiledComponent.fromTiled(this.tiled);

  @override
  void update(double dt) {}

  @override
  void render(Canvas canvas) {
    tiled.render(canvas);
  }

  Future<ObjectGroup> getObjectGroupFromLayer(String name) {
    return tiled.getObjectGroupFromLayer(name);
  }
}
