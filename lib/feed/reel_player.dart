import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/jellyfin_models.dart';
import 'feed_controller.dart';

/// Plays a single clip of a [ReelEntry]. The clip window (start/end offset)
/// is handed to mpv directly via [Media.start]/[Media.end] so it is applied
/// before the first frame decodes — seeking manually after `open()` races
/// against metadata still loading and tends to snap back to position 0.
/// `PlaylistMode.single` then makes mpv loop that same window forever, so
/// the ~1 minute clip repeats until the viewer swipes to the next reel.
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

    await player.setPlaylistMode(PlaylistMode.single);
    await player.open(
      Media(
        uri.toString(),
        start: widget.entry.clipStart,
        end: widget.entry.clipStart + widget.entry.clipDuration,
      ),
      play: true,
    );
    if (!mounted) {
      player.dispose();
      return;
    }
    setState(() => _ready = true);
  }

  void _teardownPlayer() {
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
