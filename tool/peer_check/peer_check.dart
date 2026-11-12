// Checks the real online connection in a browser: hosts a game, joins it
// with the code through the public PeerJS server, and sends messages both
// ways. Results show in the page title and the browser console.
//
//   dart compile js -o tool/peer_check/main.js tool/peer_check/peer_check.dart
//   cp web/peerjs.min.js tool/peer_check/
//   python -m http.server 8765 -d tool/peer_check
//
// Then open http://localhost:8765 in Chrome. Needs internet.

import 'dart:async';
import 'dart:js_interop';

import 'package:tanks/peer_web.dart';
import 'package:web/web.dart' as web;

void log(String s) {
  web.console.log('PEERCHECK $s'.toJS);
  web.document.title = s;
}

Future<void> main() async {
  try {
    final host = await hostGame();
    log('hosted code ${host.code}');
    final guest = await joinGame(host.code);
    final hostLink = await host.opponent;
    log('connected');

    final toHost = Completer<String>();
    final toGuest = Completer<String>();
    hostLink.onMessage = toHost.complete;
    guest.onMessage = toGuest.complete;
    guest.send('from guest');
    hostLink.send('from host');
    log(
      'host got: ${await toHost.future.timeout(const Duration(seconds: 10))}',
    );
    log(
      'guest got: ${await toGuest.future.timeout(const Duration(seconds: 10))}',
    );

    final closed = Completer<void>();
    hostLink.onClose = closed.complete;
    guest.close();
    await closed.future.timeout(const Duration(seconds: 15));
    log('host saw guest leave');
  } catch (e) {
    log('FAIL $e');
  }
  try {
    await joinGame('x9x9');
    log('FAIL wrong code accepted');
  } catch (e) {
    log('wrong code -> $e');
  }
  log('DONE');
}
