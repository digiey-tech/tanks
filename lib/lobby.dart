import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main.dart';
import 'online.dart';
import 'peer.dart' as peer;

/// Sets up a battle between two devices: the host gets a code to share, and
/// the other player types it in to join.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({
    super.key,
    required this.host,
    this.hostGame = peer.hostGame,
    this.joinGame = peer.joinGame,
  });

  /// True to host a game, false to join one.
  final bool host;

  /// Swappable for tests.
  final Future<peer.PeerHost> Function() hostGame;
  final Future<peer.NetLink> Function(
    String code, {
    peer.StatusCallback? onStatus,
  })
  joinGame;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _codeField = TextEditingController();

  peer.PeerHost? _hosted;
  bool _busy = false;
  String? _error;

  /// Progress while joining, such as switching to the relay.
  String _status = 'Connecting…';

  @override
  void initState() {
    super.initState();
    if (widget.host) _host();
  }

  @override
  void dispose() {
    _hosted?.cancel();
    _codeField.dispose();
    super.dispose();
  }

  Future<void> _host() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final hosted = await widget.hostGame();
      if (!mounted) {
        hosted.cancel();
        return;
      }
      setState(() => _hosted = hosted);
      final link = await hosted.opponent;
      if (!mounted) {
        link.close();
        return;
      }
      _start(OnlineMatch(link: link, isHost: true));
    } on peer.NetError catch (e) {
      if (mounted) _fail(e.message);
    }
  }

  Future<void> _join() async {
    final code = _codeField.text.trim();
    if (code.length != 4) {
      setState(() => _error = 'Enter the 4-digit code from the host.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Connecting…';
    });
    try {
      final link = await widget.joinGame(
        code,
        onStatus: (status) {
          if (mounted) setState(() => _status = status);
        },
      );
      if (!mounted) {
        link.close();
        return;
      }
      _start(OnlineMatch(link: link, isHost: false));
    } on peer.NetError catch (e) {
      if (mounted) _fail(e.message);
    }
  }

  void _fail(String message) {
    setState(() {
      _busy = false;
      _hosted = null;
      _error = message;
    });
  }

  void _start(OnlineMatch match) {
    _hosted = null;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => GameScreen(online: match)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15181C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.host ? 'Host a game' : 'Join a game'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.host ? _hostView() : _joinView(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _hostView() {
    final hosted = _hosted;
    final error = _error;
    if (error != null) {
      return [
        _ErrorText(error),
        const SizedBox(height: 16),
        FilledButton(onPressed: _host, child: const Text('Try again')),
      ];
    }
    if (hosted == null) {
      return const [_Waiting('Creating a game…')];
    }
    return [
      const Text(
        'Your code',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18, color: Colors.white70),
      ),
      const SizedBox(height: 4),
      Text(
        hosted.code,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 72,
          fontWeight: FontWeight.w900,
          letterSpacing: 12,
          color: redColor,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'On the other device, open Tanks, tap Join and enter this code. '
        'You play Red; they play Blue.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15, color: Colors.white70),
      ),
      const SizedBox(height: 32),
      const _Waiting('Waiting for the other player…'),
    ];
  }

  List<Widget> _joinView() {
    final error = _error;
    return [
      const Text(
        'Enter the code shown on the host’s screen.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, color: Colors.white70),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _codeField,
        enabled: !_busy,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.go,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        onSubmitted: (_) => _join(),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.w900,
          letterSpacing: 12,
        ),
        decoration: const InputDecoration(
          hintText: '0000',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      if (_busy)
        _Waiting(_status)
      else
        FilledButton(
          onPressed: _join,
          style: FilledButton.styleFrom(
            backgroundColor: blueColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          child: const Text('Join'),
        ),
      if (error != null) ...[const SizedBox(height: 16), _ErrorText(error)],
      const SizedBox(height: 16),
      const Text(
        'You play Blue. Your tank is shown at the bottom of your screen.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: Colors.white54),
      ),
    ];
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(text, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 16, color: Color(0xFFFF8A80)),
    );
  }
}
