/// A two-way message channel to the other device.
abstract class NetLink {
  void send(String message);

  /// Called for each message from the other device.
  abstract void Function(String message)? onMessage;

  /// Called once if the other device disconnects or the connection drops.
  abstract void Function()? onClose;

  /// True when messages go through the relay server instead of straight
  /// between the devices.
  bool get relayed;

  void close();
}

/// A game waiting for an opponent to join with [code].
abstract class PeerHost {
  String get code;

  /// Completes when an opponent connects.
  Future<NetLink> get opponent;

  /// Stops waiting and frees the code.
  void cancel();
}

/// A problem connecting, with a message to show the player.
class NetError implements Exception {
  const NetError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Progress messages while joining, such as switching to the relay.
typedef StatusCallback = void Function(String status);
