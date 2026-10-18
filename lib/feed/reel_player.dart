import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/jellyfin_models.dart';
import 'feed_controller.dart';

/// Plays a single clip of a [ReelEntry]: opens the stream at the chosen
/// random offset, plays for the chosen clip duration, then calls
/// [onClipFinished] so the feed can advance. Only [isActive] players
/// actually decode video; inactive ones stay paused/disposed-lazily to
/// save battery and bandwidth.
class ReelPlayerView extends StatefulWidget {
  final JellyfinSession session;
  final ReelEntry entry;
  final bool isActive;
  final VoidCallback onClipFinished;

  const ReelPlayerView({
    super.key,
    required this.session,
    required this.entry,
    required this.isActive,
    required this.onClipFinished,
  });

  @override
  State<ReelPlayerView> createState() => _ReelPlayerViewState();
}

class _ReelPlayerViewState extends State<ReelPlayerView> {
  Player? _player;
  VideoController? _controller;
  Timer? _clipTimer;
  bool _ready = false;

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

    await player.open(Media(uri.toString()), play: false);
    await player.seek(widget.entry.clipStart);
    await player.play();
    if (!mounted) {
      player.dispose();
      return;
    }
    setState(() => _ready = true);

    _clipTimer?.cancel();
    _clipTimer = Timer(widget.entry.clipDuration, () {
      if (mounted) widget.onClipFinished();
    });
  }

  void _teardownPlayer() {
    _clipTimer?.cancel();
    _clipTimer = null;
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
      _clipTimer?.cancel();
    } else {
      player.play();
      final remaining = widget.entry.clipDuration - player.state.position;
      if (remaining > Duration.zero) {
        _clipTimer = Timer(remaining, () {
          if (mounted) widget.onClipFinished();
        });
      }
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
              Center(child: Video(controller: _controller!, fit: BoxFit.contain))
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
