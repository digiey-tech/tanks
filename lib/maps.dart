import 'package:flutter/painting.dart';

/// An arena layout: the wall blocks in a 300 × 420 arena.
///
/// Every layout looks the same after turning it 180° around the center, so
/// neither player's side has an advantage, and all keep the two starting
/// spots (150, 50) and (150, 370) clear. test/maps_test.dart checks both,
/// and that every open spot can be driven to.
class GameMap {
  const GameMap(this.name, this.walls);

  final String name;
  final List<Rect> walls;

  /// The original layout: four bars and a center block.
  static const classic = GameMap('Classic', [
    Rect.fromLTWH(40, 128, 72, 16),
    Rect.fromLTWH(188, 128, 72, 16),
    Rect.fromLTWH(40, 276, 72, 16),
    Rect.fromLTWH(188, 276, 72, 16),
    Rect.fromLTWH(134, 194, 32, 32),
  ]);

  /// Mostly open, with small pillars to duck behind.
  static const pillars = GameMap('Pillars', [
    Rect.fromLTWH(63, 128, 24, 24),
    Rect.fromLTWH(213, 128, 24, 24),
    Rect.fromLTWH(63, 268, 24, 24),
    Rect.fromLTWH(213, 268, 24, 24),
    Rect.fromLTWH(138, 198, 24, 24),
  ]);

  /// Two long walls with gaps at opposite ends, so the way across zigzags.
  /// Good for bounce shots along the lanes.
  static const zigzag = GameMap('Zigzag', [
    Rect.fromLTWH(0, 140, 200, 14),
    Rect.fromLTWH(100, 266, 200, 14),
    Rect.fromLTWH(135, 195, 30, 30),
  ]);

  /// A bar shielding each starting spot, with cover along the sides.
  static const bunkers = GameMap('Bunkers', [
    Rect.fromLTWH(110, 92, 80, 12),
    Rect.fromLTWH(110, 316, 80, 12),
    Rect.fromLTWH(30, 170, 12, 80),
    Rect.fromLTWH(258, 170, 12, 80),
    Rect.fromLTWH(140, 200, 20, 20),
  ]);

  /// A broken cross through the middle, open at the center.
  static const crossroads = GameMap('Crossroads', [
    Rect.fromLTWH(144, 100, 12, 70),
    Rect.fromLTWH(144, 250, 12, 70),
    Rect.fromLTWH(40, 204, 70, 12),
    Rect.fromLTWH(190, 204, 70, 12),
  ]);

  /// Every map, in menu order. Online play sends a map as its index here,
  /// so only add new maps to the end.
  static const all = [classic, pillars, zigzag, bunkers, crossroads];
}
