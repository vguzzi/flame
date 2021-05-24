import 'dart:math' as math;
import 'dart:async';
import 'dart:ui';

import 'package:flame/extensions.dart';
import 'package:flame/flame.dart';
import 'package:flame/palette.dart';
import 'package:flame/sprite.dart';
import 'package:tiled/tiled.dart';

/// Tiled represents all flips and rotation using three possible flips: horizontal, vertical and diagonal.
/// This class converts that representation to a simpler one, that uses one angle (with pi/2 steps) and two flips (H or V).
/// More reference: https://doc.mapeditor.org/en/stable/reference/tmx-map-format/#tile-flipping
class _SimpleFlips {
  /// The angle (in steps of pi/2 rads), clockwise, around the center of the tile.
  final int angle;

  /// Whether to flip across a central vertical axis (passing through the center).
  final bool flipH;

  /// Whether to flip across a central horizontal axis (passing through the center).
  final bool flipV;

  _SimpleFlips(this.angle, this.flipH, this.flipV);

  /// This is the conversion from the truth table that I drew.
  factory _SimpleFlips.fromFlips(Flips flips) {
    int angle;
    bool flipV, flipH;

    if (!flips.diagonally && !flips.vertically && !flips.horizontally) {
      angle = 0;
      flipV = false;
      flipH = false;
    } else if (!flips.diagonally && !flips.vertically && flips.horizontally) {
      angle = 0;
      flipV = false;
      flipH = true;
    } else if (!flips.diagonally && flips.vertically && !flips.horizontally) {
      angle = 0;
      flipV = true;
      flipH = false;
    } else if (!flips.diagonally && flips.vertically && flips.horizontally) {
      angle = 2;
      flipV = false;
      flipH = false;
    } else if (flips.diagonally && !flips.vertically && !flips.horizontally) {
      angle = 1;
      flipV = false;
      flipH = true;
    } else if (flips.diagonally && !flips.vertically && flips.horizontally) {
      angle = 1;
      flipV = false;
      flipH = false;
    } else if (flips.diagonally && flips.vertically && !flips.horizontally) {
      angle = 3;
      flipV = false;
      flipH = false;
    } else if (flips.diagonally && flips.vertically && flips.horizontally) {
      angle = 1;
      flipV = true;
      flipH = false;
    } else {
      // this should be exhaustive
      throw 'Invalid combination of booleans: $flips';
    }

    return _SimpleFlips(angle, flipH, flipV);
  }
}

/// This component renders a tile map based on a TMX file from Tiled.
class Tiled {
  static final Paint _paint = BasicPalette.white.paint();

  String fileName;
  Vector2? destTileSize;

  late TiledMap map;
  late Image image;
  Map<String, SpriteBatch> batches = {};

  Tiled._({
    required this.fileName,
    this.destTileSize,
  });

  /// Creates this Tiled with the filename (for the tmx file resource)
  /// and destTileSize is the tile size to be rendered (not the tile size in
  /// the texture, that one is configured inside Tiled).
  static Future<Tiled> loadTmxFile(
    String fileName,
    Vector2? destTileSize,
  ) async {
    final tiled = Tiled._(fileName: fileName, destTileSize: destTileSize);

    final contents = await Flame.bundle.loadString('assets/tiles/$fileName');
    tiled.map = TileMapParser.parseTmx(contents);

    tiled.image = await Flame.images.load(tiled.map.tilesets[0].image!.source!);
    tiled.batches = await _loadImages(tiled.map);
    tiled.generate();

    return tiled;
  }

  static Future<Map<String, SpriteBatch>> _loadImages(TiledMap map) async {
    final fs = map.tilesets.map((t) {
      final key = t.image!.source!;
      return SpriteBatch.load(key).then((e) => MapEntry(key, e));
    });
    final fs2 = await Future.wait(fs);
    return Map.fromEntries(fs2);
  }

  /// Generate the sprite batches from the existing tilemap.
  void generate() {
    for (var batch in batches.values) {
      batch.clear();
    }
    _drawTiles(map);
  }

  void _drawTiles(TiledMap map) {
    map.layers
        .whereType<TileLayer>()
        .where((layer) => layer.visible)
        .forEach((layer) {
      layer.tileData!.forEach((tileRow) {
        tileRow.forEach((tileData) {
          if (tileData.tile == 0) {
            return;
          }
          final tileset = map.tilesetByTileGId(tileData.tile);
          final tile = map.tileByGid(tileData.tile);
          final rect = tileset.computeDrawRect(tile);

          final batch = batches[tile.image!.source]!;

          final src = Rect.fromLTWH(
            rect.left.toDouble(),
            rect.top.toDouble(),
            rect.width.toDouble(),
            rect.height.toDouble(),
          );

          final flips = _SimpleFlips.fromFlips(tileData.flips);
          final tileSize = destTileSize ??
              Vector2(tile.width.toDouble(), tile.height.toDouble());

          final p = Vector2Extension.fromInts(tile.x, tile.y);
          batch.add(
            source: src,
            offset: (p..multiply(tileSize)) +
                Vector2(
                  (tileData.flips.horizontally ? tileSize.x : 0),
                  (tileData.flips.vertically ? tileSize.y : 0),
                ),
            rotation: flips.angle * math.pi / 2,
            scale: tileSize.x / tile.width,
          );
        });
      });
    });
  }

  void render(Canvas c) {
    batches.forEach((_, batch) {
      batch.render(c);
    });
  }

  /// This returns an object group fetch by name from a given layer.
  /// Use this to add custom behaviour to special objects and groups.
  ObjectGroup getObjectGroupFromLayer(String name) {
    return map.layers
        .whereType<ObjectGroup>()
        .firstWhere((objectGroup) => objectGroup.name == name);
  }
}
