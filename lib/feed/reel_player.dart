import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/jellyfin_models.dart';
import 'feed_controller.dart';

/// Plays a single ~1 minute clip of a [ReelEntry] on repeat. The start offset
/// is handed to mpv via [Media.start] (seeking right after `open()` races
/// metadata loading and snaps back to 0); the loop back to the clip start is
/// driven by the position stream.
class ReelPlayerView extends StatefulWidget {
  final JellyfinSession session;
  final ReelEntry entry;
  final bool isActive;

  const ReelPlayerView({
    super.key,
    required this.session,
    required this.entry,
    required this.isActive,
  });

  @override
  State<ReelPlayerView> createState() => _ReelPlayerViewState();
}

class _ReelPlayerViewState extends State<ReelPlayerView> {
  Player? _player;
  VideoController? _controller;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _completedSub;
  bool _ready = false;
  bool _seeking = false;

  Duration get _clipEnd => widget.entry.clipStart + widget.entry.clipDuration;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _initPlayer();
    }
  }

  @override
  void didUpdateWidget(covariant ReelPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _initPlayer();
    } else if (!widget.isActive && oldWidget.isActive) {
      _teardownPlayer();
    }
  }

  Future<void> _initPlayer() async {
    final player = Player();
    final controller = VideoController(player);
    final uri = JellyfinClient.streamUrl(widget.session, widget.entry.item);

    setState(() {
      _player = player;
      _controller = controller;
      _ready = false;
    });

    // mpv's own looping restarts at 0, not at the clip start, so the loop
    // is driven from here by watching the position.
    _positionSub = player.stream.position.listen((pos) {
      if (pos >= _clipEnd) _restartClip();
    });
    _completedSub = player.stream.completed.listen((done) {
      if (done) _restartClip();
    });

    await player.open(
      Media(uri.toString(), start: widget.entry.clipStart),
      play: true,
    );
    if (!mounted || _player != player) {
      return;
    }
    setState(() => _ready = true);
  }

  Future<void> _restartClip() async {
    final player = _player;
    if (player == null || _seeking) return;
    _seeking = true;
    await player.seek(widget.entry.clipStart);
    await player.play();
    _seeking = false;
  }

  void _teardownPlayer() {
    _positionSub?.cancel();
    _positionSub = null;
    _completedSub?.cancel();
    _completedSub = null;
    _player?.dispose();
    _player = null;
    _controller = null;
    _ready = false;
  }

  void _togglePause() {
    final player = _player;
    if (player == null) return;
    if (player.state.playing) {
      player.pause();
    } else {
      player.play();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _teardownPlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.entry.item;
    return GestureDetector(
      onTap: _togglePause,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_controller != null && _ready)
              Center(
                child: Video(
                  controller: _controller!,
                  fit: BoxFit.contain,
                  controls: NoVideoControls,
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white54),
              ),
            if (_player != null && !_player!.state.playing && _ready)
              const Center(
                child: Icon(Icons.play_arrow, size: 72, color: Colors.white70),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 32,
              child: _InfoOverlay(item: item),
            ),
            if (_player != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: StreamBuilder<Duration>(
                  stream: _player!.stream.position,
                  builder: (context, snapshot) {
                    final pos = snapshot.data ?? widget.entry.clipStart;
                    final elapsed = pos - widget.entry.clipStart;
                    final total = widget.entry.clipDuration.inMilliseconds;
                    final value = total > 0
                        ? (elapsed.inMilliseconds / total).clamp(0.0, 1.0)
                        : 0.0;
                    return LinearProgressIndicator(
                      value: value,
                      minHeight: 3,
                      backgroundColor: Colors.white24,
                      color: Colors.white,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoOverlay extends StatelessWidget {
  final JellyfinItem item;
  const _InfoOverlay({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.displayTitle,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(blurRadius: 8, color: Colors.black)],
          ),
        ),
        if (item.displaySubtitle.isNotEmpty)
          Text(
            item.displaySubtitle,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              shadows: [Shadow(blurRadius: 8, color: Colors.black)],
            ),
          ),
      ],
    );
  }
}
