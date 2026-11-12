import 'net.dart';

const _webOnly = NetError(
  'Online play only works in the web version of the game.',
);

Future<PeerHost> hostGame() async => throw _webOnly;

Future<NetLink> joinGame(String code) async => throw _webOnly;
