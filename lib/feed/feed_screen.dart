import 'package:flutter/material.dart';

import '../jellyfin/jellyfin_models.dart';
import '../jellyfin/session_store.dart';
import 'feed_controller.dart';
import 'reel_player.dart';

class FeedScreen extends StatefulWidget {
  final JellyfinSession session;
  final VoidCallback onLoggedOut;

  const FeedScreen({super.key, required this.session, required this.onLoggedOut});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late final FeedController _feed;
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _feed = FeedController(widget.session);
    _feed.addListener(_onFeedChanged);
    _feed.start();
  }

  void _onFeedChanged() {
    if (mounted) setState(() {});
  }

  void _advance() {
    if (!mounted) return;
    final next = _currentIndex + 1;
    if (next < _feed.queue.length) {
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    _feed.ensureAhead(index);
  }

  Future<void> _logout() async {
    await SessionStore.clear();
    widget.onLoggedOut();
  }

  @override
  void dispose() {
    _feed.removeListener(_onFeedChanged);
    _feed.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final queue = _feed.queue;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            if (queue.isEmpty)
              Center(
                child: _feed.error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _feed.error!,
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : const CircularProgressIndicator(color: Colors.white54),
              )
            else
              PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: queue.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  return ReelPlayerView(
                    session: widget.session,
                    entry: queue[index],
                    isActive: index == _currentIndex,
                    onClipFinished: _advance,
                  );
                },
              ),
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white70),
                  tooltip: 'Abmelden',
                  onPressed: _logout,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
