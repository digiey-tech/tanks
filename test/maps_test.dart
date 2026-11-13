import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tanks/ai.dart';
import 'package:tanks/game.dart';
import 'package:tanks/maps.dart';

void main() {
  const world = TankGame.world;

  for (final map in GameMap.all) {
    group(map.name, () {
      test('looks the same turned around, so neither side is favored', () {
        Rect turned(Rect r) => Rect.fromLTWH(
          world.width - r.right,
          world.height - r.bottom,
          r.width,
          r.height,
        );
        for (final wall in map.walls) {
          expect(map.walls, contains(turned(wall)), reason: '$wall');
        }
      });

      test('keeps walls inside the arena and the starting spots clear', () {
        final game = TankGame(map: map);
        for (final wall in map.walls) {
          expect((Offset.zero & world).contains(wall.topLeft), isTrue);
          expect(wall.right, lessThanOrEqualTo(world.width));
          expect(wall.bottom, lessThanOrEqualTo(world.height));
        }
        expect(game.isOpen(game.red.spawn, margin: 4), isTrue);
        expect(game.isOpen(game.blue.spawn, margin: 4), isTrue);
      });

      test('every open spot can be driven to', () {
        final game = TankGame(map: map);
        const step = 4.0;
        final columns = (world.width / step).floor();
        final rows = (world.height / step).floor();
        Offset at(int c, int r) => Offset(c * step + 2, r * step + 2);

        final open = <(int, int)>{
          for (var c = 0; c < columns; c++)
            for (var r = 0; r < rows; r++)
              if (game.isOpen(at(c, r))) (c, r),
        };
        final start = (
          (game.red.spawn.dx / step).floor(),
          (game.red.spawn.dy / step).floor(),
        );
        final seen = <(int, int)>{start};
        final queue = Queue.of([start]);
        while (queue.isNotEmpty) {
          final (c, r) = queue.removeFirst();
          for (final next in [(c + 1, r), (c - 1, r), (c, r + 1), (c, r - 1)]) {
            if (open.contains(next) && seen.add(next)) queue.add(next);
          }
        }
        expect(open.difference(seen), isEmpty);
        expect(
          seen.contains((
            (game.blue.spawn.dx / step).floor(),
            (game.blue.spawn.dy / step).floor(),
          )),
          isTrue,
        );
      });

      test('a CPU match plays out to a winner', () {
        final game = TankGame(map: map);
        final hard = TankAi(
          game: game,
          tank: game.blue,
          difficulty: Difficulty.hard,
          random: math.Random(7),
        );
        final easy = TankAi(
          game: game,
          tank: game.red,
          difficulty: Difficulty.easy,
          random: math.Random(8),
        );
        for (var t = 0.0; t < 120 && !game.isOver; t += 1 / 60) {
          hard.update(1 / 60);
          easy.update(1 / 60);
          game.update(1 / 60);
        }
        expect(game.isOver, isTrue);
        expect(game.winner, Team.blue);
      });
    });
  }

  test('a random-map game picks a different map each round', () {
    final game = TankGame(map: null);
    var last = game.map;
    final seen = {last};
    for (var i = 0; i < 20; i++) {
      game.reset();
      expect(game.map, isNot(same(last)));
      last = game.map;
      seen.add(last);
    }
    expect(seen.length, greaterThan(2));
  });

  test('online guests play on the host’s map', () {
    final host = TankGame(map: GameMap.zigzag);
    final guest = TankGame()..applySnapshot(host.toSnapshot());
    expect(guest.map, same(GameMap.zigzag));
    expect(guest.walls, GameMap.zigzag.walls);
  });
}
