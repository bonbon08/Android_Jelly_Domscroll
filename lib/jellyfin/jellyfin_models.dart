class JellyfinSession {
  final String serverUrl;
  final String accessToken;
  final String userId;

  const JellyfinSession({
    required this.serverUrl,
    required this.accessToken,
    required this.userId,
  });

  Map<String, String> get authHeaders => {'X-Emby-Token': accessToken};
}

class JellyfinItem {
  final String id;
  final String name;
  final String type; // "Movie" or "Episode"
  final String? seriesName;
  final String? seriesId;
  final int? indexNumber;
  final int? parentIndexNumber;
  final Duration runtime;
  final String? mediaSourceId;

  const JellyfinItem({
    required this.id,
    required this.name,
    required this.type,
    required this.runtime,
    this.seriesName,
    this.seriesId,
    this.indexNumber,
    this.parentIndexNumber,
    this.mediaSourceId,
  });

  /// Groups items that should count as "the same thing" for variety purposes:
  /// episodes of the same series share a group, movies are their own group.
  String get groupKey => type == 'Episode' ? (seriesId ?? id) : id;

  String get displayTitle {
    if (type == 'Episode') {
      final season = parentIndexNumber != null
          ? 'S${parentIndexNumber!.toString().padLeft(2, '0')}'
          : '';
      final episode = indexNumber != null
          ? 'E${indexNumber!.toString().padLeft(2, '0')}'
          : '';
      final tag = (season.isNotEmpty || episode.isNotEmpty)
          ? ' $season$episode'
          : '';
      return '${seriesName ?? name}$tag';
    }
    return name;
  }

  String get displaySubtitle => type == 'Episode' ? name : '';

  factory JellyfinItem.fromJson(Map<String, dynamic> json) {
    final ticks = json['RunTimeTicks'] as int?;
    final sources = json['MediaSources'] as List?;
    final sourceId = (sources != null && sources.isNotEmpty)
        ? sources.first['Id'] as String?
        : null;
    return JellyfinItem(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? '',
      type: json['Type'] as String? ?? 'Movie',
      seriesName: json['SeriesName'] as String?,
      seriesId: json['SeriesId'] as String?,
      indexNumber: json['IndexNumber'] as int?,
      parentIndexNumber: json['ParentIndexNumber'] as int?,
      runtime: Duration(microseconds: (ticks ?? 0) ~/ 10),
      mediaSourceId: sourceId,
    );
  }
}
