import 'dart:io';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../../core/utils/media_scanner.dart';

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

  // Pause/cancel token
  CancelToken? cancelToken;
  bool _pauseRequested = false;

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
}

class DownloaderService extends GetxController {
  final YoutubeExplode _yt = YoutubeExplode();

  RxList<dynamic> searchResults = [].obs;
  RxList<DownloadTask> activeDownloads = <DownloadTask>[].obs;
  RxList<DownloadTask> completedDownloads = <DownloadTask>[].obs;
  RxBool isSearching = false.obs;
  RxString searchError = ''.obs;

  // ─── Search ────────────────────────────────────────────────
  Future<void> searchMusic(String query) async {
    if (query.trim().isEmpty) return;
    searchResults.clear();
    isSearching.value = true;
    searchError.value = '';
    try {
      final results = await _yt.search.search(query);
      searchResults.assignAll(results);
    } catch (e) {
      searchError.value = 'Search failed. Check your connection.';
    } finally {
      isSearching.value = false;
    }
  }

  // ─── Preview stream URL (for in-app preview) ───────────────
  Future<String?> getPreviewUrl(String videoId) async {
    try {
      final manifest =
          await _yt.videos.streamsClient.getManifest(VideoId(videoId));
      final audio = manifest.audioOnly;
      if (audio.isEmpty) return null;
      return audio.withHighestBitrate().url.toString();
    } catch (_) {
      return null;
    }
  }

  // ─── Queue download ────────────────────────────────────────
  Future<void> queueDownload(dynamic video, DownloadFormat format) async {
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
    _processDownload(task);
  }

  Future<void> _processDownload(DownloadTask task) async {
    task.clearPauseRequest();
    try {
      task.status.value = DownloadStatus.connecting;
      task.statusLabel.value = 'Connecting...';

      final ok = await _requestPermission();
      if (!ok) {
        _fail(task, 'Storage permission denied');
        return;
      }

      final manifest =
          await _yt.videos.streamsClient.getManifest(VideoId(task.videoId));
      final audioStreams = manifest.audioOnly;
      if (audioStreams.isEmpty) {
        _fail(task, 'No audio stream found');
        return;
      }

      final streamInfo = audioStreams.withHighestBitrate();
      final streamUrl = streamInfo.url.toString();
      final totalBytes = streamInfo.size.totalBytes;
      final kbps = (streamInfo.bitrate.bitsPerSecond / 1000).round();
      task.statusLabel.value = 'Stream found · ${kbps}kbps';

      final saveDir = await _getMusicDir();
      final safeName = _sanitize(task.title);
      final ext = _extFor(task.format);
      final filePath = '${saveDir.path}/$safeName.$ext';

      // Check if partially downloaded (for resume)
      final file = File(filePath);
      int existingBytes = 0;
      if (await file.exists()) {
        existingBytes = await file.length();
      }

      task.status.value = DownloadStatus.downloading;
      task.statusLabel.value = 'Downloading...';
      task.cancelToken = CancelToken();

      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(minutes: 10),
        // Increase receive buffer for faster downloads
        headers: {
          'Connection': 'keep-alive',
          if (existingBytes > 0) 'Range': 'bytes=$existingBytes-',
        },
      ));

      int downloaded = existingBytes;
      int lastBytes = existingBytes;
      DateTime lastTime = DateTime.now();

      final sink = file.openWrite(
          mode: existingBytes > 0 ? FileMode.append : FileMode.write);

      try {
        final response = await dio.get<ResponseBody>(
          streamUrl,
          cancelToken: task.cancelToken,
          options: Options(responseType: ResponseType.stream),
        );

        await for (final chunk in response.data!.stream) {
          if (task.pauseRequested) {
            await sink.flush();
            await sink.close();
            task.status.value = DownloadStatus.paused;
            task.statusLabel.value = 'Paused · tap resume';
            task.speed.value = '';
            return;
          }

          sink.add(chunk);
          downloaded += chunk.length;

          if (totalBytes > 0) {
            task.progress.value = downloaded / totalBytes;
          }

          final now = DateTime.now();
          final ms = now.difference(lastTime).inMilliseconds;
          if (ms >= 400) {
            final bps = ((downloaded - lastBytes) / ms * 1000).round();
            task.speed.value = _fmtSpeed(bps);
            task.statusLabel.value =
                '${task.speed.value} · ${_fmtBytes(downloaded)}/${_fmtBytes(totalBytes)}';
            lastBytes = downloaded;
            lastTime = now;
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      // Done
      await MediaScanner.scanFile(filePath);
      task.filePath = filePath;
      task.progress.value = 1.0;
      task.status.value = DownloadStatus.done;
      task.statusLabel.value = 'Saved to Music ✓';
      task.speed.value = '';
      activeDownloads.remove(task);
      completedDownloads.insert(0, task);
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        // Cancelled — ignore
        return;
      }
      _fail(
          task,
          e.toString().length > 80
              ? '${e.toString().substring(0, 80)}...'
              : e.toString());
    }
  }

  void pauseTask(DownloadTask task) {
    if (task.status.value == DownloadStatus.downloading) {
      task.requestPause();
    }
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
    activeDownloads.remove(task);
    completedDownloads.remove(task);
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
    task.cancelToken?.cancel();
    activeDownloads.remove(task);
  }

  void clearCompleted() => completedDownloads.clear();

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

  @override
  void onClose() {
    _yt.close();
    super.onClose();
  }
}
