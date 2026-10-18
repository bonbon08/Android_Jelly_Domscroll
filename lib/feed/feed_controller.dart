import 'dart:math';
import 'package:flutter/foundation.dart';

import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/jellyfin_models.dart';

/// One item scheduled to appear in the feed, together with the random
/// clip window (start offset + duration) chosen for this particular showing.
class ReelEntry {
  final JellyfinItem item;
  final Duration clipStart;
  final Duration clipDuration;

  ReelEntry({
    required this.item,
    required this.clipStart,
    required this.clipDuration,
  });
}

/// Builds and maintains an endless, shuffled queue of reel-style clips from
/// not-yet-watched movies/episodes. Guarantees that consecutive entries never
/// come from the same movie/series, and picks a fresh random scene each time
/// an item is scheduled so repeats never look identical.
class FeedController extends ChangeNotifier {
  final JellyfinSession session;
  final Random _random = Random();

  static const Duration minClip = Duration(seconds: 15);
  static const Duration maxClip = Duration(seconds: 30);
  static const int _refillThreshold = 8;
  static const int _fetchLimit = 60;

  final List<ReelEntry> _queue = [];
  final List<JellyfinItem> _pool = [];
  bool _loading = false;
  String? _error;

  FeedController(this.session);

  List<ReelEntry> get queue => List.unmodifiable(_queue);
  bool get loading => _loading;
  String? get error => _error;

  Future<void> start() async {
    await _refillPool();
    _growQueue(12);
    notifyListeners();
  }

  /// Call when the viewer reaches near the end of the current queue.
  Future<void> ensureAhead(int currentIndex) async {
    if (_queue.length - currentIndex <= _refillThreshold) {
      if (_pool.length < _refillThreshold) {
        await _refillPool();
      }
      _growQueue(10);
      notifyListeners();
    }
  }

  Future<void> _refillPool() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final items = await JellyfinClient.fetchUnwatched(session, limit: _fetchLimit);
      items.shuffle(_random);
      _pool.addAll(items);
      if (items.isEmpty && _pool.isEmpty) {
        _error = 'Keine ungesehenen Filme oder Folgen gefunden.';
      }
    } catch (e) {
      _error = 'Fehler beim Laden: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _growQueue(int count) {
    for (var i = 0; i < count && _pool.isNotEmpty; i++) {
      final item = _pickNext();
      if (item == null) break;
      _queue.add(_buildEntry(item));
    }
  }

  /// Picks the next item from the pool, avoiding the same movie/series as the
  /// previous queue entry whenever an alternative exists.
  JellyfinItem? _pickNext() {
    if (_pool.isEmpty) return null;
    final lastGroup = _queue.isNotEmpty ? _queue.last.item.groupKey : null;

    var index = _pool.indexWhere((it) => it.groupKey != lastGroup);
    if (index == -1) index = 0;

    return _pool.removeAt(index);
  }

  ReelEntry _buildEntry(JellyfinItem item) {
    final total = item.runtime;
    final clipLen = Duration(
      seconds: minClip.inSeconds +
          _random.nextInt(maxClip.inSeconds - minClip.inSeconds + 1),
    );
    final effectiveClip = clipLen > total ? total : clipLen;
    final latestStart = total - effectiveClip;
    final startSeconds = latestStart.inSeconds > 0
        ? _random.nextInt(latestStart.inSeconds)
        : 0;
    return ReelEntry(
      item: item,
      clipStart: Duration(seconds: startSeconds),
      clipDuration: effectiveClip,
    );
  }
}
