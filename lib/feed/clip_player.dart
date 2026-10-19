import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../jellyfin/stream_proxy.dart';
import 'feed_controller.dart';

/// The one player shared by the whole feed. Switching reels only opens new
/// media on it. Creating and disposing a player per reel tore down
/// media_kit's per-player EGL context while the raster thread could still be
/// using it, which on Linux could leave the window showing a frozen picture
/// while audio kept playing.
class ClipPlayer extends ChangeNotifier {
  final Future<StreamProxy> proxy;
  final Player player = Player();
  late final VideoController video = VideoController(player);

  ReelEntry? _entry;
  ReelEntry? _readyEntry;
  int _generation = 0;
  bool _seeking = false;
  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<bool> _completedSub;
  late final StreamSubscription<bool> _playingSub;

  ClipPlayer(this.proxy) {
    // mpv's own looping restarts at 0, not at the clip start, so the loop
    // is driven from here.
    _positionSub = player.stream.position.listen((pos) {
      final entry = _entry;
      if (entry != null && _readyEntry == entry && pos >= _clipEnd(entry)) {
        _restartClip();
      }
    });
    _completedSub = player.stream.completed.listen((done) {
      if (done && _readyEntry != null) _restartClip();
    });
    _playingSub = player.stream.playing.listen((_) => notifyListeners());
  }

  bool isReadyFor(ReelEntry entry) => identical(_readyEntry, entry);
  bool get playing => player.state.playing;

  static Duration _clipEnd(ReelEntry e) => e.clipStart + e.clipDuration;

  Future<void> play(ReelEntry entry) async {
    if (identical(_entry, entry)) return;
    final gen = ++_generation;
    _entry = entry;
    _readyEntry = null;
    notifyListeners();

    final uri = (await proxy).streamUrl(entry.item);
    if (gen != _generation) return;
    // The start offset goes to mpv as a file option: seeking right after
    // open() races metadata loading and snaps back to 0.
    await player.open(
      Media(uri.toString(), start: entry.clipStart),
      play: true,
    );
    if (gen != _generation) return;
    _readyEntry = entry;
    notifyListeners();
  }

  Future<void> _restartClip() async {
    final entry = _entry;
    if (entry == null || _seeking) return;
    _seeking = true;
    await player.seek(entry.clipStart);
    await player.play();
    _seeking = false;
  }

  void togglePause() {
    if (player.state.playing) {
      player.pause();
    } else {
      player.play();
    }
  }

  @override
  void dispose() {
    _positionSub.cancel();
    _completedSub.cancel();
    _playingSub.cancel();
    player.dispose();
    super.dispose();
  }
}
