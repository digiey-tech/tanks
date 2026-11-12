// Checks the real online connection in a browser: hosts a game, joins it with
// the code, and sends messages both ways, first directly and then forced
// through the relay. Results show in the page and the browser console.
//
//   dart compile js -o tool/peer_check/main.js tool/peer_check/peer_check.dart
//   cp web/peerjs.min.js tool/peer_check/
//   python -m http.server 8765 -d tool/peer_check
//
// Then open http://localhost:8765 in Chrome. Needs internet. To check a
// relay running locally (npm run dev in relay/), add
// ?relay=ws://127.0.0.1:8787 to the address.

import 'dart:async';
import 'dart:js_interop';

import 'package:tanks/net.dart';
import 'package:tanks/peer_web.dart';
import 'package:web/web.dart' as web;

void log(String s) {
  web.console.log('PEERCHECK $s'.toJS);
  web.document.body!.append(web.HTMLDivElement()..textContent = s);
}

Future<void> battle(String name) async {
  final host = await hostGame();
  final statuses = <String>[];
  final guest = await joinGame(host.code, onStatus: statuses.add);
  final hostLink = await host.opponent.timeout(const Duration(seconds: 10));
  log(
    '$name: connected with code ${host.code}, '
    '${guest.relayed ? 'via relay' : 'direct'} '
    '(host sees ${hostLink.relayed ? 'relay' : 'direct'})'
    '${statuses.isEmpty ? '' : ', status: ${statuses.join(' / ')}'}',
  );

  final toHost = Completer<String>();
  final toGuest = Completer<String>();
  hostLink.onMessage = toHost.complete;
  guest.onMessage = toGuest.complete;
  guest.send('from guest');
  hostLink.send('from host');
  log(
    '$name: host got "${await toHost.future.timeout(const Duration(seconds: 10))}"',
  );
  log(
    '$name: guest got "${await toGuest.future.timeout(const Duration(seconds: 10))}"',
  );

  final closed = Completer<void>();
  hostLink.onClose = closed.complete;
  guest.close();
  await closed.future.timeout(const Duration(seconds: 15));
  log('$name: host saw the guest leave');
}

Future<void> main() async {
  final relay = Uri.base.queryParameters['relay'];
  if (relay != null) relayUrl = relay;
  log('relay: $relayUrl');

  try {
    await battle('normal');
  } catch (e) {
    log('FAIL normal: $e');
  }

  debugSkipDirect = true;
  try {
    await battle('forced relay');
  } catch (e) {
    log('FAIL forced relay: $e');
  }
  debugSkipDirect = false;

  debugStallDirect = true;
  try {
    await battle('blocked direct');
  } catch (e) {
    log('FAIL blocked direct: $e');
  }
  debugStallDirect = false;

  try {
    await joinGame('x9x9');
    log('FAIL wrong code accepted');
  } on NetError catch (e) {
    log('wrong code: $e');
  }
  log('DONE');
}
