import 'dart:io';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:resonance/core/utils/media_scanner.dart';

enum DownloadFormat { mp3, flac, m4a }

enum DownloadStatus { queued, connecting, downloading, converting, done, error }

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
  DateTime startedAt = DateTime.now();

  DownloadTask({
    required this.videoId,
    required this.title,
    required this.author,
    required this.thumbnail,
    required this.format,
  });

  String get formatLabel => format.name.toUpperCase();
}

class DownloaderService extends GetxController {
  final YoutubeExplode _yt = YoutubeExplode();
  final Dio _dio = Dio();

  RxList<Video> searchResults = <Video>[].obs;
  RxList<DownloadTask> activeDownloads = <DownloadTask>[].obs;
  RxList<DownloadTask> completedDownloads = <DownloadTask>[].obs;

  RxBool isSearching = false.obs;
  RxString searchError = ''.obs;

  // Active count for badge
  int get activeCount => activeDownloads
      .where((t) =>
          t.status.value == DownloadStatus.downloading ||
          t.status.value == DownloadStatus.connecting ||
          t.status.value == DownloadStatus.converting)
      .length;

  // ─── Search ───────────────────────────────────────────────
  Future<void> searchMusic(String query) async {
    if (query.trim().isEmpty) return;
    searchResults.clear();
    isSearching.value = true;
    searchError.value = '';
    try {
      final results = await _yt.search.search(query);
      searchResults.assignAll(results);
    } catch (e) {
      searchError.value = 'Search failed. Check your internet connection.';
    } finally {
      isSearching.value = false;
    }
  }

  // ─── Queue Download ───────────────────────────────────────
  Future<void> queueDownload(Video video, DownloadFormat format) async {
    // Prevent duplicate
    final exists = activeDownloads
        .any((t) => t.videoId == video.id.value && t.format == format);
    if (exists) return;

    final task = DownloadTask(
      videoId: video.id.value,
      title: video.title,
      author: video.author,
      thumbnail: video.thumbnails.mediumResUrl,
      format: format,
    );
    activeDownloads.add(task);
    _processDownload(task); // fire-and-forget
  }

  Future<void> _processDownload(DownloadTask task) async {
    try {
      // Step 1: Permission
      task.status.value = DownloadStatus.connecting;
      task.statusLabel.value = 'Requesting permission...';

      final hasPermission = await _requestStoragePermission();
      if (!hasPermission) {
        _failTask(task, 'Storage permission denied');
        return;
      }

      // Step 2: Connect & fetch stream info
      task.statusLabel.value = 'Connecting to source...';
      final manifest =
          await _yt.videos.streamsClient.getManifest(VideoId(task.videoId));

      // Audio-only streams
      final audioStreams = manifest.audioOnly;
      if (audioStreams.isEmpty) {
        _failTask(task, 'No audio stream found');
        return;
      }

      // Pick best bitrate
      final streamInfo = audioStreams.withHighestBitrate();
      final totalBytes = streamInfo.size.totalBytes;
      final bitrateKbps = (streamInfo.bitrate.bitsPerSecond / 1000).round();
      task.statusLabel.value = 'Found stream · ${bitrateKbps}kbps';

      await Future.delayed(const Duration(milliseconds: 400));

      // Step 3: Prepare file path
      final saveDir = await _getMusicDirectory();
      final safeName = _sanitize(task.title);
      final ext = _ext(task.format);
      final filePath = '${saveDir.path}/$safeName.$ext';

      // Step 4: Download
      task.status.value = DownloadStatus.downloading;
      task.statusLabel.value = 'Downloading...';

      final stream = _yt.videos.streamsClient.get(streamInfo);
      final file = File(filePath);
      final sink = file.openWrite();
      int downloaded = 0;
      int lastBytes = 0;
      DateTime lastTime = DateTime.now();

      await for (final chunk in stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        task.progress.value = downloaded / totalBytes;

        // Calculate speed every ~500ms
        final now = DateTime.now();
        final elapsed = now.difference(lastTime).inMilliseconds;
        if (elapsed >= 500) {
          final bytesPerSec = ((downloaded - lastBytes) / elapsed * 1000);
          task.speed.value = _formatSpeed(bytesPerSec.round());
          task.statusLabel.value =
              'Downloading · ${task.speed.value} · ${_formatBytes(downloaded)}/${_formatBytes(totalBytes)}';
          lastBytes = downloaded;
          lastTime = now;
        }
      }
      await sink.flush();
      await sink.close();

      // Step 5: Media scan (make visible to other apps)
      task.status.value = DownloadStatus.converting;
      task.statusLabel.value = 'Saving to library...';
      await MediaScanner.scanFile(filePath);
      await Future.delayed(const Duration(milliseconds: 500));

      // Step 6: Done
      task.filePath = filePath;
      task.status.value = DownloadStatus.done;
      task.statusLabel.value = 'Saved to Music folder ✓';
      task.speed.value = '';
      task.progress.value = 1.0;

      // Move to completed list
      activeDownloads.remove(task);
      completedDownloads.insert(0, task);
    } catch (e) {
      _failTask(
          task,
          e.toString().length > 80
              ? '${e.toString().substring(0, 80)}...'
              : e.toString());
    }
  }

  void _failTask(DownloadTask task, String msg) {
    task.status.value = DownloadStatus.error;
    task.statusLabel.value = msg;
    task.errorMessage = msg;
  }

  // ─── Helpers ──────────────────────────────────────────────
  String _ext(DownloadFormat f) {
    return switch (f) {
      DownloadFormat.mp3 => 'mp3',
      DownloadFormat.flac => 'flac',
      DownloadFormat.m4a => 'm4a',
    };
  }

  String _sanitize(String name) => name
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .substring(0, name.length.clamp(0, 80));

  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec > 1024 * 1024) {
      return '${(bytesPerSec / 1024 / 1024).toStringAsFixed(1)} MB/s';
    } else if (bytesPerSec > 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(0)} KB/s';
    }
    return '$bytesPerSec B/s';
  }

  String _formatBytes(int bytes) {
    if (bytes > 1024 * 1024)
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
    return '${(bytes / 1024).toStringAsFixed(0)}KB';
  }

  Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.audio.isGranted) return true;
    final r = await Permission.audio.request();
    if (r.isGranted) return true;
    final r2 = await Permission.storage.request();
    return r2.isGranted;
  }

  Future<Directory> _getMusicDirectory() async {
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

  void retryTask(DownloadTask task) {
    activeDownloads.remove(task);
    completedDownloads.remove(task);
    final newTask = DownloadTask(
      videoId: task.videoId,
      title: task.title,
      author: task.author,
      thumbnail: task.thumbnail,
      format: task.format,
    );
    activeDownloads.add(newTask);
    _processDownload(newTask);
  }

  void clearCompleted() => completedDownloads.clear();

  @override
  void onClose() {
    _yt.close();
    super.onClose();
  }
}
