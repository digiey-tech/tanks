/// Connects two devices for online play. The real implementation runs in the
/// browser using PeerJS; other platforms (and tests) get a stub that explains
/// online play needs the web version.
library;

export 'net.dart';
export 'peer_stub.dart' if (dart.library.js_interop) 'peer_web.dart';
