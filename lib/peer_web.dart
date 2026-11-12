import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

import 'net.dart';

/// Where to load PeerJS from. The app ships its own copy next to index.html,
/// and only loads it when someone picks online play.
String peerJsUrl = 'peerjs.min.js';

/// Prefix for room IDs on the shared PeerJS server, so a code only ever
/// matches another copy of this game. Bump the version if the messages
/// between devices change in an incompatible way.
const _idPrefix = 'digiey-tanks-v1-';

const _connectTimeout = Duration(seconds: 15);

@JS('Peer')
extension type _Peer._(JSObject _) implements JSObject {
  external _Peer([String? id]);
  external void on(String event, JSFunction callback);
  external _Connection connect(String id, [JSObject? options]);
  external void destroy();
}

extension type _Connection._(JSObject _) implements JSObject {
  external void on(String event, JSFunction callback);
  external void send(JSAny data);
  external void close();
}

Future<void>? _loading;

Future<void> _loadPeerJs() {
  if (globalContext.has('Peer')) return Future.value();
  return _loading ??= () {
    final done = Completer<void>();
    final script = web.HTMLScriptElement()..src = peerJsUrl;
    script.onload = ((web.Event _) => done.complete()).toJS;
    script.onerror = ((web.Event _) {
      _loading = null;
      done.completeError(
        const NetError(
          'Could not load online play. Check your internet connection.',
        ),
      );
    }).toJS;
    web.document.head!.append(script);
    return done.future;
  }();
}

String? _errorType(JSAny? error) {
  if (error == null || !error.isA<JSObject>()) return null;
  return (error as JSObject).getProperty<JSAny?>('type'.toJS)?.dartify()
      as String?;
}

NetError _describe(String? type) => NetError(switch (type) {
  'peer-unavailable' =>
    'No game found with that code. Check the code, and that the other '
        'player is still waiting.',
  'network' ||
  'socket-error' ||
  'socket-closed' ||
  'server-error' ||
  'disconnected' ||
  'ssl-unavailable' =>
    'Could not reach the matchmaking server. Check your internet '
        'connection.',
  'browser-incompatible' => "This browser doesn't support online play.",
  _ =>
    "Couldn't connect the two devices. If you're on school or public "
        'Wi-Fi, try connecting both to a phone hotspot.',
});

class _PeerLink implements NetLink {
  _PeerLink(this._peer, this._connection) {
    _connection.on(
      'data',
      ((JSAny? data) {
        final message = data?.dartify();
        if (message is String) onMessage?.call(message);
      }).toJS,
    );
    _connection.on('close', (() => _dropped()).toJS);
    _connection.on('error', ((JSAny? _) => _dropped()).toJS);
  }

  final _Peer _peer;
  final _Connection _connection;
  bool _open = true;

  @override
  void Function(String message)? onMessage;

  @override
  void Function()? onClose;

  @override
  void send(String message) {
    if (_open) _connection.send(message.toJS);
  }

  @override
  void close() {
    if (!_open) return;
    _open = false;
    _connection.close();
    _peer.destroy();
  }

  void _dropped() {
    if (!_open) return;
    _open = false;
    _peer.destroy();
    onClose?.call();
  }
}

class _Host implements PeerHost {
  _Host(this.code, this._peer) {
    _peer.on(
      'connection',
      ((_Connection connection) {
        // Only one opponent per game.
        if (_opponent.isCompleted) {
          connection.close();
          return;
        }
        connection.on(
          'open',
          (() {
            if (!_opponent.isCompleted) {
              _opponent.complete(_PeerLink(_peer, connection));
            }
          }).toJS,
        );
      }).toJS,
    );
  }

  @override
  final String code;
  final _Peer _peer;
  final _opponent = Completer<NetLink>();

  @override
  Future<NetLink> get opponent => _opponent.future;

  /// A server error while still waiting; once connected, the devices talk
  /// directly and no longer need the server.
  void _fail(String? type) {
    if (_opponent.isCompleted) return;
    _opponent.completeError(_describe(type));
    _peer.destroy();
  }

  @override
  void cancel() {
    if (_opponent.isCompleted) return;
    _opponent.completeError(const NetError('Cancelled.'));
    _peer.destroy();
  }
}

Future<PeerHost> hostGame() async {
  await _loadPeerJs();
  final random = math.Random();
  for (var attempt = 0; attempt < 5; attempt++) {
    final code = random.nextInt(10000).toString().padLeft(4, '0');
    final peer = _Peer('$_idPrefix$code');
    final registered = Completer<void>();
    _Host? host;
    peer.on(
      'open',
      ((JSAny? _) {
        if (!registered.isCompleted) registered.complete();
      }).toJS,
    );
    peer.on(
      'error',
      ((JSAny? error) {
        final type = _errorType(error);
        if (!registered.isCompleted) {
          registered.completeError(type ?? 'unknown');
        } else {
          host?._fail(type);
        }
      }).toJS,
    );
    try {
      await registered.future.timeout(_connectTimeout);
      return host = _Host(code, peer);
    } on TimeoutException {
      peer.destroy();
      throw _describe('network');
    } on String catch (type) {
      peer.destroy();
      // Someone else is using this code right now; pick another.
      if (type == 'unavailable-id') continue;
      throw _describe(type);
    }
  }
  throw const NetError('Could not create a game. Please try again.');
}

Future<NetLink> joinGame(String code) async {
  await _loadPeerJs();
  final peer = _Peer();
  final connected = Completer<NetLink>();
  peer.on(
    'open',
    ((JSAny? _) {
      final connection = peer.connect(
        '$_idPrefix$code',
        {'reliable': true, 'serialization': 'json'}.jsify() as JSObject,
      );
      connection.on(
        'open',
        (() {
          if (!connected.isCompleted) {
            connected.complete(_PeerLink(peer, connection));
          }
        }).toJS,
      );
    }).toJS,
  );
  peer.on(
    'error',
    ((JSAny? error) {
      if (!connected.isCompleted) {
        connected.completeError(_describe(_errorType(error)));
      }
    }).toJS,
  );
  try {
    return await connected.future.timeout(_connectTimeout);
  } on TimeoutException {
    peer.destroy();
    throw _describe('webrtc');
  } catch (_) {
    peer.destroy();
    rethrow;
  }
}
