import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:get/get.dart';

enum DownloadFormat { mp3, mp4, flac }

enum DownloadStatus { idle, searching, downloading, done, error }

class DownloadTask {
  final String videoId;
  final String title;
  final String thumbnail;
  final DownloadFormat format;
  RxDouble progress = 0.0.obs;
  Rx<DownloadStatus> status = DownloadStatus.idle.obs;
  String? filePath;
  String? errorMessage;

  DownloadTask({
    required this.videoId,
    required this.title,
    required this.thumbnail,
    required this.format,
  });
}

class DownloaderService extends GetxController {
  final YoutubeExplode _yt = YoutubeExplode();
  final Dio _dio = Dio();

  RxList<Video> searchResults = <Video>[].obs;
  RxList<DownloadTask> downloadQueue = <DownloadTask>[].obs;
  Rx<DownloadStatus> searchStatus = DownloadStatus.idle.obs;
  RxString searchError = ''.obs;

  // ─── Search ───────────────────────────────────────────────
  Future<void> searchMusic(String query) async {
    if (query.trim().isEmpty) return;
    searchResults.clear();
    searchStatus.value = DownloadStatus.searching;
    searchError.value = '';

    try {
      final results = await _yt.search.search(query);
      searchResults.assignAll(results);
      searchStatus.value = DownloadStatus.idle;
    } catch (e) {
      searchStatus.value = DownloadStatus.error;
      searchError.value = 'Search failed: ${e.toString()}';
    }
  }

  // ─── Download ─────────────────────────────────────────────
  Future<void> downloadTrack(Video video, DownloadFormat format) async {
    final task = DownloadTask(
      videoId: video.id.value,
      title: video.title,
      thumbnail: video.thumbnails.mediumResUrl,
      format: format,
    );
    downloadQueue.add(task);
    task.status.value = DownloadStatus.downloading;

    try {
      // 1. Check & request storage permission
      final hasPermission = await _requestStoragePermission();
      if (!hasPermission) {
        task.status.value = DownloadStatus.error;
        task.errorMessage = 'Storage permission denied';
        return;
      }

      // 2. Get the save directory
      final saveDir = await _getMusicDirectory();

      // 3. Sanitize filename
      final safeName = video.title
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .substring(0, video.title.length.clamp(0, 80));
      final ext = format == DownloadFormat.mp4 ? 'mp4' : 'mp3';
      final filePath = '${saveDir.path}/$safeName.$ext';

      if (format == DownloadFormat.mp4) {
        await _downloadVideo(video.id, filePath, task);
      } else {
        await _downloadAudio(video.id, filePath, task);
      }

      task.filePath = filePath;
      task.status.value = DownloadStatus.done;
    } catch (e) {
      task.status.value = DownloadStatus.error;
      task.errorMessage = e.toString();
    }
  }

  Future<void> _downloadAudio(
      VideoId videoId, String filePath, DownloadTask task) async {
    final manifest = await _yt.videos.streamsClient.getManifest(videoId);
    final streamInfo = manifest.audioOnly.withHighestBitrate();
    final stream = _yt.videos.streamsClient.get(streamInfo);

    final file = File(filePath);
    final sink = file.openWrite();
    final totalBytes = streamInfo.size.totalBytes;
    int downloaded = 0;

    await for (final chunk in stream) {
      sink.add(chunk);
      downloaded += chunk.length;
      task.progress.value = downloaded / totalBytes;
    }
    await sink.flush();
    await sink.close();
  }

  Future<void> _downloadVideo(
      VideoId videoId, String filePath, DownloadTask task) async {
    final manifest = await _yt.videos.streamsClient.getManifest(videoId);
    final streamInfo = manifest.muxed.withHighestBitrate();

    final response = await _dio.download(
      streamInfo.url.toString(),
      filePath,
      onReceiveProgress: (received, total) {
        if (total > 0) task.progress.value = received / total;
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Download failed: HTTP ${response.statusCode}');
    }
  }

  // ─── Permissions & Directory ──────────────────────────────
  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      if (await Permission.audio.isGranted) return true;
      final result = await Permission.audio.request();
      if (result.isGranted) return true;
      // Fallback for older Android
      final legacy = await Permission.storage.request();
      return legacy.isGranted;
    }
    return true;
  }

  Future<Directory> _getMusicDirectory() async {
    // Tries external Music folder first, falls back to app documents
    try {
      final extDirs =
          await getExternalStorageDirectories(type: StorageDirectory.music);
      if (extDirs != null && extDirs.isNotEmpty) {
        final dir = extDirs.first;
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir;
      }
    } catch (_) {}
    // Fallback
    final appDir = await getApplicationDocumentsDirectory();
    final musicDir = Directory('${appDir.path}/Music');
    if (!await musicDir.exists()) await musicDir.create(recursive: true);
    return musicDir;
  }

  void removeFromQueue(DownloadTask task) => downloadQueue.remove(task);
  void clearCompleted() =>
      downloadQueue.removeWhere((t) => t.status.value == DownloadStatus.done);

  @override
  void onClose() {
    _yt.close();
    super.onClose();
  }
}
