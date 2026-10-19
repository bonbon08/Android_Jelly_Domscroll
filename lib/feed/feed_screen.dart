import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/jellyfin_models.dart';
import '../jellyfin/session_store.dart';
import '../jellyfin/stream_proxy.dart';
import 'clip_player.dart';
import 'feed_controller.dart';
import 'reel_player.dart';

class FeedScreen extends StatefulWidget {
  final JellyfinSession session;
  final VoidCallback onLoggedOut;

  const FeedScreen({
    super.key,
    required this.session,
    required this.onLoggedOut,
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  // How far (as a fraction of the screen height) a swipe needs to travel
  // before it counts as "next/previous reel". Kept low on purpose: the
  // default PageView threshold (~50%) felt like it needed way too much
  // scrolling before anything happened.
  static const double _dragFraction = 0.12;
  static const double _flingVelocity = 250;

  late final FeedController _feed;
  late final Future<StreamProxy> _proxy;
  late final ClipPlayer _clipPlayer;
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  double _dragAccum = 0;
  DateTime _lastWheelJump = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _proxy = StreamProxy.start(widget.session);
    _clipPlayer = ClipPlayer(_proxy);
    _feed = FeedController(widget.session);
    _feed.addListener(_onFeedChanged);
    _feed.start();
  }

  void _onFeedChanged() {
    if (!mounted) return;
    final queue = _feed.queue;
    if (_currentIndex < queue.length) {
      _clipPlayer.play(queue[_currentIndex]);
    }
    setState(() {});
  }

  void _goToPage(int target) {
    final clamped = target.clamp(0, _feed.queue.length - 1);
    if (clamped == _currentIndex) return;
    _pageController.animateToPage(
      clamped,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    _dragAccum += details.delta.dy;
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final threshold = MediaQuery.of(context).size.height * _dragFraction;
    final velocity = details.primaryVelocity ?? 0;
    if (_dragAccum <= -threshold || velocity <= -_flingVelocity) {
      _goToPage(_currentIndex + 1);
    } else if (_dragAccum >= threshold || velocity >= _flingVelocity) {
      _goToPage(_currentIndex - 1);
    }
    _dragAccum = 0;
  }

  // A single wheel notch (or a touchpad swipe, which fires many events)
  // should move exactly one reel, so further events are ignored briefly.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final now = DateTime.now();
    if (now.difference(_lastWheelJump) < const Duration(milliseconds: 450)) {
      return;
    }
    final dy = event.scrollDelta.dy;
    if (dy.abs() < 1) return;
    _lastWheelJump = now;
    _goToPage(_currentIndex + (dy > 0 ? 1 : -1));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _goToPage(_currentIndex + 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _goToPage(_currentIndex - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    _clipPlayer.play(_feed.queue[index]);
    _feed.ensureAhead(index);
  }

  Future<void> _logout() async {
    _clipPlayer.player.stop();
    await JellyfinClient.logout(widget.session);
    await SessionStore.clear();
    widget.onLoggedOut();
  }

  @override
  void dispose() {
    _feed.removeListener(_onFeedChanged);
    _feed.dispose();
    _clipPlayer.dispose();
    _proxy.then((p) => p.close());
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
              Focus(
                autofocus: true,
                onKeyEvent: _onKey,
                child: Listener(
                  onPointerSignal: _onPointerSignal,
                  child: GestureDetector(
                    onVerticalDragUpdate: _onVerticalDragUpdate,
                    onVerticalDragEnd: _onVerticalDragEnd,
                    child: PageView.builder(
                      controller: _pageController,
                      scrollDirection: Axis.vertical,
                      // Swipe handling is done manually above with a much lower
                      // threshold; PageView itself only reacts to animateToPage.
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: queue.length,
                      onPageChanged: _onPageChanged,
                      itemBuilder: (context, index) {
                        return ReelPlayerView(
                          entry: queue[index],
                          isActive: index == _currentIndex,
                          clipPlayer: _clipPlayer,
                        );
                      },
                    ),
                  ),
                ),
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
