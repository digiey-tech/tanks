import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

import 'net.dart';

/// Where to load PeerJS from. The app ships its own copy next to index.html,
/// and only loads it when someone picks online play.
String peerJsUrl = 'peerjs.min.js';

/// The relay server (the relay/ folder of this repo), used when the network
/// blocks a direct link. Empty turns the relay off.
String relayUrl = 'wss://tanks-relay.tanks-relay.workers.dev';

/// For testing the relay: never try a direct link.
bool debugSkipDirect = false;

/// For testing the fallback: a joining device's direct link never finishes
/// connecting, as on a network that blocks it.
bool debugStallDirect = false;

/// Prefix for room IDs on the shared PeerJS server, so a code only ever
/// matches another copy of this game. Bump the version if the messages
/// between devices change in an incompatible way.
const _idPrefix = 'digiey-tanks-v1-';

/// How long a joining device tries a direct link before also trying the
/// relay.
const _directHeadStart = Duration(seconds: 4);

const _attemptTimeout = Duration(seconds: 15);

/// The guest's first message, sent on whichever route connected first, so
/// the host uses the same one.
const _hello = '{"t":"hello"}';

class _NotFound extends NetError {
  const _NotFound()
    : super(
        'No game found with that code. Check the code, and that the other '
        'player is still waiting.',
      );
}

/// The host picked a code someone else is already using.
class _CodeTaken implements Exception {
  const _CodeTaken();
}

NetError _describe(String? type) => switch (type) {
  'peer-unavailable' => const _NotFound(),
  'network' ||
  'socket-error' ||
  'socket-closed' ||
  'server-error' ||
  'disconnected' ||
  'ssl-unavailable' => const NetError(
    'Could not reach the game servers. Check your internet connection.',
  ),
  'browser-incompatible' => const NetError(
    "This browser doesn't support online play.",
  ),
  _ => const NetError(
    "Couldn't connect the two devices. Please try again in a moment.",
  ),
};

// ---------------------------------------------------------------------------
// PeerJS (direct links)

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

class _PeerLink implements NetLink {
  _PeerLink(this._peer, this._connection, {required this.ownsPeer}) {
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

  /// Whether closing this link also shuts down the PeerJS peer. Off for a
  /// host's candidate links, so one failed candidate doesn't stop others.
  bool ownsPeer;
  bool _open = true;

  @override
  void Function(String message)? onMessage;

  @override
  void Function()? onClose;

  @override
  bool get relayed => false;

  @override
  void send(String message) {
    if (_open) _connection.send(message.toJS);
  }

  @override
  void close() {
    if (!_open) return;
    _open = false;
    _connection.close();
    if (ownsPeer) _peer.destroy();
  }

  void _dropped() {
    if (!_open) return;
    _open = false;
    if (ownsPeer) _peer.destroy();
    onClose?.call();
  }
}

/// Registers [code] with the PeerJS server so a guest can find this host.
Future<_Peer> _registerPeer(String code) async {
  await _loadPeerJs();
  final peer = _Peer('$_idPrefix$code');
  final registered = Completer<void>();
  peer.on(
    'open',
    ((JSAny? _) {
      if (!registered.isCompleted) registered.complete();
    }).toJS,
  );
  peer.on(
    'error',
    ((JSAny? error) {
      if (!registered.isCompleted) {
        registered.completeError(_errorType(error) ?? 'unknown');
      }
    }).toJS,
  );
  try {
    await registered.future.timeout(_attemptTimeout);
    return peer;
  } on TimeoutException {
    peer.destroy();
    throw _describe('network');
  } on String catch (type) {
    peer.destroy();
    if (type == 'unavailable-id') throw const _CodeTaken();
    throw _describe(type);
  }
}

_Attempt _joinDirect(String code) {
  _Peer? peer;
  var cancelled = false;
  final connected = Completer<NetLink>();
  () async {
    try {
      await _loadPeerJs();
    } on NetError catch (e) {
      if (!connected.isCompleted) connected.completeError(e);
      return;
    }
    if (cancelled) return;
    final p = peer = _Peer();
    p.on(
      'open',
      ((JSAny? _) {
        final connection = p.connect(
          '$_idPrefix$code',
          {'reliable': true, 'serialization': 'json'}.jsify() as JSObject,
        );
        connection.on(
          'open',
          (() {
            if (!connected.isCompleted && !debugStallDirect) {
              connected.complete(_PeerLink(p, connection, ownsPeer: true));
            }
          }).toJS,
        );
      }).toJS,
    );
    p.on(
      'error',
      ((JSAny? error) {
        if (!connected.isCompleted) {
          connected.completeError(_describe(_errorType(error)));
        }
      }).toJS,
    );
  }();
  void cancel() {
    cancelled = true;
    peer?.destroy();
  }

  return _Attempt(
    connected.future.timeout(_attemptTimeout).catchError((Object e) {
      cancel();
      throw e is NetError ? e : _describe('webrtc');
    }),
    cancel,
  );
}

// ---------------------------------------------------------------------------
// Relay (fallback over a normal secure WebSocket)

class _RelayLink implements NetLink {
  _RelayLink(this._socket) {
    _socket.onmessage = ((web.MessageEvent event) {
      final data = event.data.dartify();
      if (data is! String) return;
      if (data == '{"t":"_left"}') {
        _dropped();
      } else if (data != 'pong' && !data.startsWith('{"t":"_')) {
        onMessage?.call(data);
      }
    }).toJS;
    _socket.onclose = ((web.CloseEvent _) => _dropped()).toJS;
    // Keeps the connection from being dropped as idle while a host waits.
    // The server answers these without waking up.
    _keepAlive = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_open) _socket.send('ping'.toJS);
    });
  }

  final web.WebSocket _socket;
  late final Timer _keepAlive;
  bool _open = true;

  @override
  void Function(String message)? onMessage;

  @override
  void Function()? onClose;

  @override
  bool get relayed => true;

  @override
  void send(String message) {
    if (_open) _socket.send(message.toJS);
  }

  @override
  void close() {
    if (!_open) return;
    _open = false;
    _keepAlive.cancel();
    _socket.close();
  }

  void _dropped() {
    if (!_open) return;
    _open = false;
    _keepAlive.cancel();
    _socket.close();
    onClose?.call();
  }
}

/// Connects to the relay room for [code]. The returned future completes once
/// the server lets this device in.
({web.WebSocket socket, Future<web.WebSocket> ready}) _openRelay(
  String code,
  String role,
) {
  final socket = web.WebSocket('$relayUrl/room/$code?role=$role');
  final ready = Completer<web.WebSocket>();
  socket.onmessage = ((web.MessageEvent event) {
    if (!ready.isCompleted && event.data.dartify() == '{"t":"_ok"}') {
      ready.complete(socket);
    }
  }).toJS;
  socket.onclose = ((web.CloseEvent event) {
    if (ready.isCompleted) return;
    ready.completeError(switch (event.code) {
      4404 => const _NotFound(),
      4409 when role == 'host' => const _CodeTaken(),
      4409 => const NetError('That game already has two players.'),
      _ => _describe('network'),
    });
  }).toJS;
  return (
    socket: socket,
    ready: ready.future.timeout(
      _attemptTimeout,
      onTimeout: () {
        socket.close();
        throw _describe('network');
      },
    ),
  );
}

_Attempt _joinRelay(String code) {
  final (:socket, :ready) = _openRelay(code, 'guest');
  return _Attempt(ready.then(_RelayLink.new), () => socket.close());
}

// ---------------------------------------------------------------------------
// Hosting and joining

/// One way of connecting that's in progress.
class _Attempt {
  _Attempt(this.link, this.cancel);

  final Future<NetLink> link;
  final void Function() cancel;
}

class _Host implements PeerHost {
  _Host(this.code, this._peer, web.WebSocket? relay) {
    final peer = _peer;
    if (peer != null) {
      peer.on(
        'connection',
        ((_Connection connection) {
          if (_opponent.isCompleted) {
            connection.close();
            return;
          }
          connection.on(
            'open',
            (() {
              if (_opponent.isCompleted) {
                connection.close();
              } else {
                _watch(_PeerLink(peer, connection, ownsPeer: false));
              }
            }).toJS,
          );
        }).toJS,
      );
      peer.on(
        'error',
        ((JSAny? error) {
          // New direct links are no longer possible, but the relay may be.
          _peerFailed = true;
          _failIfStuck(_describe(_errorType(error)));
        }).toJS,
      );
    }
    if (relay != null) _watch(_relay = _RelayLink(relay));
  }

  @override
  final String code;
  final _Peer? _peer;
  _RelayLink? _relay;
  bool _peerFailed = false;
  final _candidates = <NetLink>[];
  final _opponent = Completer<NetLink>();

  @override
  Future<NetLink> get opponent => _opponent.future;

  /// Waits on a possible link for the guest's hello.
  void _watch(NetLink link) {
    _candidates.add(link);
    link.onMessage = (message) {
      if (message == _hello) _choose(link);
    };
    link.onClose = () {
      _candidates.remove(link);
      if (identical(link, _relay)) {
        _relay = null;
        _failIfStuck(_describe('network'));
      }
    };
  }

  void _choose(NetLink link) {
    if (_opponent.isCompleted) return;
    for (final other in _candidates) {
      if (identical(other, link)) continue;
      other
        ..onMessage = null
        ..onClose = null
        ..close();
    }
    _candidates.clear();
    if (link is _PeerLink) {
      link.ownsPeer = true;
    } else {
      _peer?.destroy();
    }
    link
      ..onMessage = null
      ..onClose = null;
    _opponent.complete(link);
  }

  /// Gives up only when neither route can bring an opponent any more.
  void _failIfStuck(NetError reason) {
    if (_opponent.isCompleted) return;
    if ((_peer == null || _peerFailed) && _relay == null) {
      _closeAll();
      _opponent.completeError(reason);
    }
  }

  void _closeAll() {
    for (final link in _candidates) {
      link
        ..onMessage = null
        ..onClose = null
        ..close();
    }
    _candidates.clear();
    _relay = null;
    _peer?.destroy();
  }

  @override
  void cancel() {
    if (_opponent.isCompleted) return;
    _closeAll();
    _opponent.completeError(const NetError('Cancelled.'));
  }
}

Future<PeerHost> hostGame() async {
  final random = math.Random();
  for (var attempt = 0; attempt < 5; attempt++) {
    final code = random.nextInt(10000).toString().padLeft(4, '0');

    web.WebSocket? relay;
    NetError? relayError;
    if (relayUrl.isNotEmpty) {
      try {
        relay = await _openRelay(code, 'host').ready;
      } on _CodeTaken {
        continue;
      } on NetError catch (e) {
        relayError = e;
      }
    }

    _Peer? peer;
    NetError? directError;
    if (!debugSkipDirect) {
      try {
        peer = await _registerPeer(code);
      } on _CodeTaken {
        relay?.close();
        continue;
      } on NetError catch (e) {
        directError = e;
      }
    }

    // Either route alone is enough to start waiting.
    if (peer == null && relay == null) {
      throw directError ?? relayError ?? _describe('network');
    }
    return _Host(code, peer, relay);
  }
  throw const NetError('Could not create a game. Please try again.');
}

/// Joins the game with [code], preferring a direct link and falling back to
/// the relay if the network blocks it.
Future<NetLink> joinGame(String code, {StatusCallback? onStatus}) {
  final done = Completer<NetLink>();
  final attempts = <_Attempt>[];
  final errors = <String, NetError>{};
  _Attempt? direct;
  _Attempt? relay;

  void finish(NetLink link, _Attempt winner) {
    if (done.isCompleted) {
      link.close();
      return;
    }
    for (final other in attempts) {
      if (!identical(other, winner)) other.cancel();
    }
    link.send(_hello);
    done.complete(link);
  }

  late void Function() startRelay;

  void failed(String route, Object error) {
    errors[route] = error is NetError ? error : _describe(null);
    if (done.isCompleted) return;
    if (route == 'direct') startRelay();
    final moreToTry = relay == null && relayUrl.isNotEmpty;
    if (errors.length == attempts.length && !moreToTry) {
      // A missing room means the code is wrong or the host left.
      final error =
          errors.values.whereType<_NotFound>().firstOrNull ??
          errors['relay'] ??
          errors['direct']!;
      done.completeError(error);
    }
  }

  void start(String route, _Attempt attempt) {
    attempts.add(attempt);
    attempt.link.then(
      (link) => finish(link, attempt),
      onError: (Object error) => failed(route, error),
    );
  }

  startRelay = () {
    if (relay != null || relayUrl.isEmpty || done.isCompleted) return;
    if (direct != null) onStatus?.call('Trying another route…');
    start('relay', relay = _joinRelay(code));
  };

  if (!debugSkipDirect) start('direct', direct = _joinDirect(code));
  if (direct == null) {
    startRelay();
  } else {
    Timer(_directHeadStart, startRelay);
  }
  if (attempts.isEmpty) {
    return Future.error(const NetError('Online play is turned off.'));
  }
  return done.future;
}
