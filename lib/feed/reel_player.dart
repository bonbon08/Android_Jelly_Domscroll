import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/jellyfin_models.dart';
import '../share/clip_exporter.dart';
import 'feed_controller.dart';

/// Plays one clip of a [ReelEntry] on repeat, uncropped, with Shorts-style
/// actions on the right. The start offset is handed to mpv via
/// [Media.start] (seeking right after `open()` races metadata loading and
/// snaps back to 0); the loop back to the clip start is driven by the
/// position stream because mpv's own loop restarts at 0.
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
  bool _exporting = false;

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

  Future<void> _share() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    messenger.showSnackBar(
      const SnackBar(content: Text('Clip wird erstellt …')),
    );
    try {
      final result = await ClipExporter.export(widget.session, widget.entry);
      messenger.hideCurrentSnackBar();
      final folder = result.savedFolder;
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.message),
          action: folder == null
              ? null
              : SnackBarAction(
                  label: 'Ordner öffnen',
                  onPressed: () => Process.run('xdg-open', [folder]),
                ),
        ),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Teilen fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void dispose() {
    _teardownPlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: Colors.black, child: _buildFrame());
  }

  Widget _buildFrame() {
    final item = widget.entry.item;
    final paused = _player != null && _ready && !_player!.state.playing;
    return GestureDetector(
      onTap: _togglePause,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_controller != null && _ready)
            Video(
              controller: _controller!,
              fit: BoxFit.contain,
              controls: NoVideoControls,
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white54),
            ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 220,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
              ),
            ),
          ),
          if (paused)
            const Center(
              child: Icon(Icons.play_arrow, size: 72, color: Colors.white70),
            ),
          Positioned(
            right: 8,
            bottom: 96,
            child: _ActionButton(
              icon: Icons.share,
              label: 'Teilen',
              busy: _exporting,
              onPressed: _exporting ? null : _share,
            ),
          ),
          Positioned(
            left: 16,
            right: 80,
            bottom: 24,
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
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.black38,
          shape: const CircleBorder(),
          child: IconButton(
            iconSize: 28,
            onPressed: onPressed,
            icon: busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(icon, color: Colors.white),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            shadows: [Shadow(blurRadius: 6, color: Colors.black)],
          ),
        ),
      ],
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
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(blurRadius: 8, color: Colors.black)],
          ),
        ),
        if (item.displaySubtitle.isNotEmpty)
          Text(
            item.displaySubtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              shadows: [Shadow(blurRadius: 8, color: Colors.black)],
            ),
          ),
      ],
    );
  }
}
