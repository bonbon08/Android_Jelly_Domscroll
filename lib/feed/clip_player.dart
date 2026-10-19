import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../jellyfin/stream_proxy.dart';
import 'feed_controller.dart';

class _Slot {
  final Player player = Player();
  late final VideoController video = VideoController(player);
  ReelEntry? entry;
  bool ready = false;
  bool seeking = false;
  int generation = 0;
  final List<StreamSubscription<Object?>> subs = [];
}

/// A fixed pool of players that buffers the reels around the current one:
/// one behind, the current, and [_ahead] ahead, each opened paused at its
/// clip start. Slot `i % poolSize` holds queue index `i`, so a slot is only
/// re-pointed at new media when its index leaves the window.
///
/// The players are created once and never disposed while the feed lives.
/// Creating/disposing a player per reel tore down media_kit's per-player EGL
/// context while the raster thread could still use it, which on Linux froze
/// the window picture while audio kept playing.
class ClipPlayer extends ChangeNotifier {
  static const int _behind = 1;
  static const int _ahead = 2;
  static const int _poolSize = _behind + 1 + _ahead;

  final Future<StreamProxy> proxy;
  final List<_Slot> _slots = List.generate(_poolSize, (_) => _Slot());
  int _current = -1;
  double _rate = 1.0;

  ClipPlayer(this.proxy) {
    for (final slot in _slots) {
      // mpv's own looping restarts at 0, not at the clip start, so the loop
      // is driven from here.
      slot.subs.add(
        slot.player.stream.position.listen((pos) {
          final entry = slot.entry;
          if (entry != null &&
              slot.ready &&
              identical(slot, _activeSlot) &&
              pos >= entry.clipStart + entry.clipDuration) {
            _restart(slot);
          }
        }),
      );
      slot.subs.add(
        slot.player.stream.completed.listen((done) {
          if (done && slot.ready && identical(slot, _activeSlot)) {
            _restart(slot);
          }
        }),
      );
      slot.subs.add(
        slot.player.stream.playing.listen((_) {
          if (identical(slot, _activeSlot)) notifyListeners();
        }),
      );
    }
  }

  _Slot? get _activeSlot => _current < 0 ? null : _slots[_current % _poolSize];

  _Slot? _slotFor(ReelEntry entry) {
    for (final s in _slots) {
      if (identical(s.entry, entry)) return s;
    }
    return null;
  }

  /// Video for [entry] once its media is loaded, also for neighbouring
  /// pages, so the next reel's frame is already visible while swiping.
  VideoController? videoFor(ReelEntry entry) {
    final slot = _slotFor(entry);
    return slot != null && slot.ready ? slot.video : null;
  }

  bool isActiveReady(ReelEntry entry) {
    final slot = _activeSlot;
    return slot != null && identical(slot.entry, entry) && slot.ready;
  }

  Player? get activePlayer => _activeSlot?.player;
  bool get playing => _activeSlot?.player.state.playing ?? false;
  double get rate => _rate;

  /// Points the pool at the window around [current] and starts that reel.
  void update(List<ReelEntry> queue, int current) {
    if (current < 0 || current >= queue.length) return;
    final previous = _activeSlot;
    _current = current;
    final active = _activeSlot!;

    // Nearest-first so the next reel starts buffering before the ones
    // further out.
    final order = [current, current + 1, current - 1, current + 2];
    for (final i in order) {
      if (i < 0 || i >= queue.length) continue;
      final slot = _slots[i % _poolSize];
      if (!identical(slot.entry, queue[i])) _load(slot, queue[i]);
    }

    if (!identical(previous, active)) {
      previous?.player.pause();
      if (active.ready) _startFromClipStart(active);
    }
    notifyListeners();
  }

  Future<void> _load(_Slot slot, ReelEntry entry) async {
    final gen = ++slot.generation;
    slot.entry = entry;
    slot.ready = false;
    final uri = (await proxy).streamUrl(entry.item);
    if (gen != slot.generation) return;
    // The start offset goes to mpv as a file option: seeking right after
    // open() races metadata loading and snaps back to 0.
    await slot.player.open(
      Media(uri.toString(), start: entry.clipStart),
      play: false,
    );
    if (gen != slot.generation) return;
    await slot.player.setRate(_rate);
    slot.ready = true;
    if (identical(slot, _activeSlot)) slot.player.play();
    notifyListeners();
  }

  Future<void> _startFromClipStart(_Slot slot) async {
    await slot.player.seek(slot.entry!.clipStart);
    if (identical(slot, _activeSlot)) await slot.player.play();
  }

  Future<void> _restart(_Slot slot) async {
    if (slot.seeking) return;
    slot.seeking = true;
    await _startFromClipStart(slot);
    slot.seeking = false;
  }

  void togglePause() {
    final player = activePlayer;
    if (player == null) return;
    if (player.state.playing) {
      player.pause();
    } else {
      player.play();
    }
  }

  void toggleDoubleSpeed() {
    _rate = _rate == 1.0 ? 2.0 : 1.0;
    for (final slot in _slots) {
      slot.player.setRate(_rate);
    }
    notifyListeners();
  }

  void stopAll() {
    for (final slot in _slots) {
      slot.generation++;
      slot.player.stop();
    }
  }

  @override
  void dispose() {
    for (final slot in _slots) {
      for (final sub in slot.subs) {
        sub.cancel();
      }
      slot.player.dispose();
    }
    super.dispose();
  }
}
