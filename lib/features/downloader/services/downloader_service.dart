import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../../core/models/download_record.dart';
import '../../../core/utils/media_scanner.dart';
import '../../../core/theme/app_theme.dart';

enum DownloadFormat { mp3, m4a, flac }

enum DownloadStatus { queued, connecting, downloading, paused, done, error }

class DownloadTask {
  final String videoId;
  final String title;
  final String author;
  final String thumbnail;
  final DownloadFormat format;

  RxDouble progress = 0.0.obs;
  RxString statusLabel = 'Queued'.obs;
  RxString speed = ''.obs;
  Rx<DownloadStatus> status = DownloadStatus.queued.obs;
  String? filePath;
  String? errorMessage;
  bool _pauseRequested = false;
  bool _cancelled = false;

  DownloadTask({
    required this.videoId,
    required this.title,
    required this.author,
    required this.thumbnail,
    required this.format,
  });

  String get formatLabel => format.name.toUpperCase();
  void requestPause() => _pauseRequested = true;
  bool get pauseRequested => _pauseRequested;
  void clearPauseRequest() => _pauseRequested = false;
  void cancel() => _cancelled = true;
  bool get cancelled => _cancelled;
}

class DownloaderService extends GetxController {
  late Box<DownloadRecord> _historyBox;

  RxList<dynamic> searchResults = [].obs;
  RxList<String> searchSuggestions = <String>[].obs;
  RxList<DownloadTask> activeDownloads = <DownloadTask>[].obs;
  RxList<DownloadRecord> downloadHistory = <DownloadRecord>[].obs;
  RxBool isSearching = false.obs;
  RxString searchError = ''.obs;

  @override
  void onInit() {
    super.onInit();
    _historyBox = Hive.box<DownloadRecord>('downloads');
    downloadHistory.assignAll(_historyBox.values.toList().reversed.toList());
  }

  // ─── Creates a fresh YT instance with multiple client fallbacks ──
  // Using multiple clients dramatically improves reliability
  YoutubeExplode _freshYt() => YoutubeExplode();

  // ─── The client list that gives us the best success rate ────────
  static final _manifestClients = [
    YoutubeApiClient.ios,
    YoutubeApiClient.androidVr,
    YoutubeApiClient.safari,
    YoutubeApiClient.android,
  ];

  // ─── Search ──────────────────────────────────────────────────────
  Future<void> searchMusic(String query) async {
    if (query.trim().isEmpty) return;
    searchResults.clear();
    searchSuggestions.clear();
    isSearching.value = true;
    searchError.value = '';

    final yt = _freshYt();
    try {
      final results = await yt.search.search(query);
      searchResults.assignAll(results);
    } catch (e) {
      searchError.value = 'Search failed. Check your connection.';
      debugPrint('Search error: $e');
    } finally {
      yt.close();
      isSearching.value = false;
    }
  }

  void updateSuggestions(String query) {
    if (query.trim().length < 2) {
      searchSuggestions.clear();
      return;
    }
    final q = query.toLowerCase();
    final titles = searchResults
        .map<String>((v) => (v.title ?? '').toString())
        .where((t) => t.toLowerCase().contains(q))
        .take(5)
        .toList();
    searchSuggestions.assignAll(titles);
  }

  // ─── Get preview URL — tries multiple clients until one works ────
  Future<String?> getPreviewUrl(String videoId) async {
    // Try each client in order — first success wins
    for (final client in _manifestClients) {
      final yt = _freshYt();
      try {
        final manifest =
            await yt.videos.streams.getManifest(videoId, ytClients: [client]);

        // audioOnly = streams with audio but no video track
        final streams = manifest.audioOnly;
        if (streams.isEmpty) continue;

        final best = streams.withHighestBitrate();
        final url = best.url.toString();
        if (url.isNotEmpty) return url;
      } catch (e) {
        debugPrint('Preview client $client failed: $e');
        continue;
      } finally {
        yt.close();
      }
    }
    return null;
  }

  // ─── Queue download ──────────────────────────────────────────────
  Future<void> queueDownload(dynamic video, DownloadFormat format) async {
    final videoId = (video.id?.value ?? video.id).toString();
    final exists =
        activeDownloads.any((t) => t.videoId == videoId && t.format == format);
    if (exists) {
      Get.snackbar('Already queued', '"${video.title}" is already downloading',
          backgroundColor: AppTheme.surface,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    final task = DownloadTask(
      videoId: videoId,
      title: video.title?.toString() ?? 'Unknown',
      author: video.author?.toString() ?? 'Unknown',
      thumbnail: video.thumbnails?.mediumResUrl?.toString() ??
          video.thumbnails?.lowResUrl?.toString() ??
          '',
      format: format,
    );
    activeDownloads.add(task);
    _processDownload(task);
  }

  Future<void> _processDownload(DownloadTask task) async {
    task.clearPauseRequest();
    String? filePath;
    YoutubeExplode? yt;

    try {
      task.status.value = DownloadStatus.connecting;
      task.statusLabel.value = 'Requesting permission...';

      final ok = await _requestPermission();
      if (!ok) {
        _fail(task, 'Storage permission denied');
        return;
      }

      final saveDir = await _getMusicDir();
      final safeName = _sanitize(task.title);
      final ext = _extFor(task.format);
      filePath = '${saveDir.path}/$safeName.$ext';
      task.filePath = filePath;

      task.statusLabel.value = 'Fetching stream info...';

      // Try each client until we get a working manifest
      StreamManifest? manifest;
      for (final client in _manifestClients) {
        if (task.cancelled) return;
        try {
          yt?.close();
          yt = _freshYt();
          manifest = await yt.videos.streams
              .getManifest(task.videoId, ytClients: [client]);

          // Verify we actually got audio streams
          if (manifest.audioOnly.isNotEmpty) {
            debugPrint('Got manifest with client: $client');
            break;
          }
        } catch (e) {
          debugPrint('Client $client failed: $e');
          manifest = null;
          continue;
        }
      }

      if (manifest == null || manifest.audioOnly.isEmpty) {
        _fail(task, 'No audio stream found. Try again later.');
        return;
      }

      final streamInfo = manifest.audioOnly.withHighestBitrate();
      final totalBytes = streamInfo.size.totalBytes;
      final kbps = (streamInfo.bitrate.bitsPerSecond / 1000).round();
      task.statusLabel.value = 'Stream ready · ${kbps}kbps';

      // Resume support
      final file = File(filePath);
      int existingBytes = 0;
      if (await file.exists()) {
        existingBytes = await file.length();
        if (totalBytes > 0 && existingBytes >= totalBytes) {
          await _completeTask(task, filePath);
          return;
        }
      }

      task.status.value = DownloadStatus.downloading;
      task.statusLabel.value = 'Downloading...';

      // Download using the stream from the same yt instance
      // that produced the manifest — DO NOT create a new instance here
      final stream = yt!.videos.streams.get(streamInfo);
      final sink = file.openWrite(
          mode: existingBytes > 0 ? FileMode.append : FileMode.write);

      int downloaded = existingBytes;
      int lastBytes = existingBytes;
      DateTime lastTime = DateTime.now();

      try {
        await for (final chunk in stream) {
          if (task.cancelled) {
            await sink.flush();
            await sink.close();
            return;
          }
          if (task.pauseRequested) {
            await sink.flush();
            await sink.close();
            task.status.value = DownloadStatus.paused;
            task.statusLabel.value =
                'Paused · ${(task.progress.value * 100).toStringAsFixed(0)}% done';
            task.speed.value = '';
            return;
          }

          sink.add(chunk);
          downloaded += chunk.length;
          if (totalBytes > 0) task.progress.value = downloaded / totalBytes;

          final now = DateTime.now();
          final ms = now.difference(lastTime).inMilliseconds;
          if (ms >= 500) {
            final bps = ((downloaded - lastBytes) / ms * 1000).round();
            task.speed.value = _fmtSpeed(bps);
            task.statusLabel.value =
                '${task.speed.value} · ${_fmtBytes(downloaded)}/${_fmtBytes(totalBytes)}';
            lastBytes = downloaded;
            lastTime = now;
          }
        }
        await sink.flush();
        await sink.close();
      } catch (e) {
        try {
          await sink.flush();
          await sink.close();
        } catch (_) {}
        rethrow;
      }

      await _completeTask(task, filePath);
    } catch (e) {
      // Clean up partial/empty file — don't pollute library
      if (filePath != null) {
        try {
          final f = File(filePath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      final msg = e.toString();
      debugPrint('Download error: $msg');
      _fail(task, msg.length > 100 ? '${msg.substring(0, 100)}...' : msg);
    } finally {
      yt?.close();
    }
  }

  Future<void> _completeTask(DownloadTask task, String filePath) async {
    await MediaScanner.scanFile(filePath);
    task.filePath = filePath;
    task.progress.value = 1.0;
    task.status.value = DownloadStatus.done;
    task.statusLabel.value = 'Saved ✓';
    task.speed.value = '';

    final record = DownloadRecord(
      videoId: task.videoId,
      title: task.title,
      author: task.author,
      thumbnail: task.thumbnail,
      filePath: filePath,
      format: task.formatLabel,
      downloadedAt: DateTime.now(),
    );
    await _historyBox.put(task.videoId + task.formatLabel, record);
    downloadHistory.insert(0, record);
    activeDownloads.remove(task);
  }

  void pauseTask(DownloadTask task) {
    if (task.status.value == DownloadStatus.downloading) task.requestPause();
  }

  void resumeTask(DownloadTask task) {
    if (task.status.value == DownloadStatus.paused) {
      task.clearPauseRequest();
      task.status.value = DownloadStatus.connecting;
      task.statusLabel.value = 'Resuming...';
      _processDownload(task);
    }
  }

  void retryTask(DownloadTask task) {
    task.cancel();
    activeDownloads.remove(task);
    final t = DownloadTask(
      videoId: task.videoId,
      title: task.title,
      author: task.author,
      thumbnail: task.thumbnail,
      format: task.format,
    );
    activeDownloads.add(t);
    _processDownload(t);
  }

  void cancelTask(DownloadTask task) {
    task.cancel();
    if (task.filePath != null) {
      try {
        final f = File(task.filePath!);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    activeDownloads.remove(task);
  }

  Future<void> deleteHistoryRecord(DownloadRecord record) async {
    try {
      final f = File(record.filePath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await _historyBox.delete(record.videoId + record.format);
    downloadHistory.remove(record);
  }

  void clearHistory() {
    _historyBox.clear();
    downloadHistory.clear();
  }

  void _fail(DownloadTask task, String msg) {
    task.status.value = DownloadStatus.error;
    task.statusLabel.value = msg;
    task.errorMessage = msg;
  }

  String _extFor(DownloadFormat f) => switch (f) {
        DownloadFormat.mp3 => 'mp3',
        DownloadFormat.flac => 'flac',
        DownloadFormat.m4a => 'm4a',
      };

  String _sanitize(String n) => n
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .substring(0, n.length.clamp(0, 80));

  String _fmtSpeed(int bps) {
    if (bps > 1024 * 1024)
      return '${(bps / 1024 / 1024).toStringAsFixed(1)} MB/s';
    if (bps > 1024) return '${(bps / 1024).toStringAsFixed(0)} KB/s';
    return '$bps B/s';
  }

  String _fmtBytes(int b) {
    if (b > 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)}MB';
    return '${(b / 1024).toStringAsFixed(0)}KB';
  }

  Future<bool> _requestPermission() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.audio.isGranted) return true;
    final r = await Permission.audio.request();
    if (r.isGranted) return true;
    return (await Permission.storage.request()).isGranted;
  }

  Future<Directory> _getMusicDir() async {
    try {
      final dirs =
          await getExternalStorageDirectories(type: StorageDirectory.music);
      if (dirs != null && dirs.isNotEmpty) {
        final d = dirs.first;
        if (!await d.exists()) await d.create(recursive: true);
        return d;
      }
    } catch (_) {}
    final app = await getApplicationDocumentsDirectory();
    final d = Directory('${app.path}/Music');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }
}
