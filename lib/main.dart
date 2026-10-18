import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'feed/feed_screen.dart';
import 'jellyfin/jellyfin_client.dart';
import 'jellyfin/jellyfin_models.dart';
import 'jellyfin/session_store.dart';
import 'login/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const JellyReelsApp());
}

class JellyReelsApp extends StatelessWidget {
  const JellyReelsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JellyReels',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const _RootGate(),
    );
  }
}

/// Decides whether to show the login screen or jump straight into the feed,
/// based on whether a saved session still validates against the server.
class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  JellyfinSession? _session;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final saved = await SessionStore.load();
    if (saved != null && await JellyfinClient.validateSession(saved)) {
      setState(() {
        _session = saved;
        _checking = false;
      });
    } else {
      setState(() => _checking = false);
    }
  }

  void _onLoggedIn(JellyfinSession session) {
    setState(() => _session = session);
  }

  void _onLoggedOut() {
    setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_session == null) {
      return LoginScreen(onLoggedIn: _onLoggedIn);
    }
    return FeedScreen(session: _session!, onLoggedOut: _onLoggedOut);
  }
}
