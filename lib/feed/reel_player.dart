import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../jellyfin/jellyfin_models.dart';
import '../share/clip_exporter.dart';
import 'clip_player.dart';
import 'feed_controller.dart';

/// One page of the feed. Only the active page shows the shared
/// [ClipPlayer]'s video; the others are just a black frame with the title.
class ReelPlayerView extends StatefulWidget {
  final ReelEntry entry;
  final bool isActive;
  final ClipPlayer clipPlayer;

  const ReelPlayerView({
    super.key,
    required this.entry,
    required this.isActive,
    required this.clipPlayer,
  });

  @override
  State<ReelPlayerView> createState() => _ReelPlayerViewState();
}

class _ReelPlayerViewState extends State<ReelPlayerView> {
  bool _exporting = false;

  Future<void> _share() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    messenger.showSnackBar(
      const SnackBar(content: Text('Clip wird erstellt …')),
    );
    try {
      final result = await ClipExporter.export(
        await widget.clipPlayer.proxy,
        widget.entry,
      );
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
  Widget build(BuildContext context) {
    final clip = widget.clipPlayer;
    return ColoredBox(
      color: Colors.black,
      child: ListenableBuilder(
        listenable: clip,
        builder: (context, _) {
          final ready = widget.isActive && clip.isReadyFor(widget.entry);
          return GestureDetector(
            onTap: ready ? clip.togglePause : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (ready)
                  Video(
                    controller: clip.video,
                    fit: BoxFit.contain,
                    controls: NoVideoControls,
                  )
                else if (widget.isActive)
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
                if (ready && !clip.playing)
                  const Center(
                    child: Icon(
                      Icons.play_arrow,
                      size: 72,
                      color: Colors.white70,
                    ),
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
                  child: _InfoOverlay(item: widget.entry.item),
                ),
                if (ready)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _ClipProgress(clip: clip, entry: widget.entry),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ClipProgress extends StatelessWidget {
  final ClipPlayer clip;
  final ReelEntry entry;

  const _ClipProgress({required this.clip, required this.entry});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: clip.player.stream.position,
      builder: (context, snapshot) {
        final pos = snapshot.data ?? entry.clipStart;
        final elapsed = pos - entry.clipStart;
        final total = entry.clipDuration.inMilliseconds;
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
