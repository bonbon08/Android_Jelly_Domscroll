import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../feed/feed_controller.dart';
import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/jellyfin_models.dart';

class ExportResult {
  final String message;

  /// Folder holding the exported file, set only when the clip was saved
  /// locally instead of being handed to a share sheet (Linux).
  final String? savedFolder;

  const ExportResult(this.message, {this.savedFolder});
}

/// Cuts the reel's clip window out of the Jellyfin stream as a vertical
/// (9:16) H.264/AAC MP4, so it plays everywhere it gets shared to.
/// Android hands the file to the system share sheet; Linux has no file
/// share sheet, so the clip is saved to the user's Videos folder instead.
class ClipExporter {
  static Future<ExportResult> export(
    JellyfinSession session,
    ReelEntry entry,
  ) async {
    final item = entry.item;
    final fileName =
        '${_sanitize(item.displayTitle)}_${_stamp(entry.clipStart)}.mp4';
    final outDir = await _outputDir();
    final outPath = '${outDir.path}/$fileName';

    final args = _ffmpegArgs(
      input: JellyfinClient.streamUrl(session, item).toString(),
      start: entry.clipStart,
      duration: entry.clipDuration,
      output: outPath,
    );

    final ok = Platform.isAndroid
        ? await _runFfmpegKit(args)
        : await _runSystemFfmpeg(args);
    if (!ok) {
      throw Exception('Clip konnte nicht erstellt werden.');
    }

    final caption = '${item.displayTitle} – ab ${_clock(entry.clipStart)}';
    if (Platform.isAndroid) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(outPath, mimeType: 'video/mp4')],
          text: caption,
        ),
      );
      return const ExportResult('Clip geteilt.');
    }
    return ExportResult('Gespeichert: $outPath', savedFolder: outDir.path);
  }

  static List<String> _ffmpegArgs({
    required String input,
    required Duration start,
    required Duration duration,
    required String output,
  }) {
    final startSec = (start.inMilliseconds / 1000).toStringAsFixed(3);
    final durSec = (duration.inMilliseconds / 1000).toStringAsFixed(3);
    return [
      '-y',
      '-ss',
      startSec,
      '-i',
      input,
      '-t',
      durSec,
      '-map',
      '0:v:0',
      '-map',
      '0:a:0?',
      '-vf',
      "crop=w='min(iw,trunc(ih*9/32)*2)':h=ih,scale=w=-2:h='min(1280,ih)'",
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '23',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-ac',
      '2',
      '-movflags',
      '+faststart',
      output,
    ];
  }

  static Future<bool> _runFfmpegKit(List<String> args) async {
    final session = await FFmpegKit.executeWithArguments(args);
    final code = await session.getReturnCode();
    return ReturnCode.isSuccess(code);
  }

  static Future<bool> _runSystemFfmpeg(List<String> args) async {
    try {
      final result = await Process.run('ffmpeg', [
        '-hide_banner',
        '-loglevel',
        'error',
        ...args,
      ]);
      return result.exitCode == 0;
    } on ProcessException {
      throw Exception('ffmpeg ist nicht installiert.');
    }
  }

  static Future<Directory> _outputDir() async {
    if (Platform.isAndroid) {
      return getTemporaryDirectory();
    }
    var videos = '${Platform.environment['HOME']}/Videos';
    try {
      final r = await Process.run('xdg-user-dir', ['VIDEOS']);
      final path = (r.stdout as String).trim();
      if (r.exitCode == 0 && path.isNotEmpty) videos = path;
    } on ProcessException {
      // xdg-user-dirs not installed; keep ~/Videos.
    }
    final dir = Directory('$videos/JellyReels');
    await dir.create(recursive: true);
    return dir;
  }

  static String _sanitize(String s) => s
      .replaceAll(RegExp(r'[^A-Za-z0-9äöüÄÖÜß]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  static String _stamp(Duration d) =>
      '${d.inHours}h${(d.inMinutes % 60).toString().padLeft(2, '0')}m${(d.inSeconds % 60).toString().padLeft(2, '0')}s';

  static String _clock(Duration d) {
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '${d.inMinutes}:$s';
  }
}
