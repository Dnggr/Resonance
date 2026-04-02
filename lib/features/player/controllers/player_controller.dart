import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class SongFile {
  final String path;
  final String name;
  final String ext;
  const SongFile({required this.path, required this.name, required this.ext});

  @override
  bool operator ==(Object other) => other is SongFile && other.path == path;
  @override
  int get hashCode => path.hashCode;
}

enum LoopMode { none, one, all }

class PlayerController extends GetxController {
  final AudioPlayer player = AudioPlayer();

  // Full library
  RxList<SongFile> songs = <SongFile>[].obs;
  // What's shown in library UI (filtered)
  RxList<SongFile> filteredSongs = <SongFile>[].obs;

  // The ACTIVE queue — what's actually playing (playlist or full library)
  // This is separate from songs/filteredSongs
  RxList<SongFile> queue = <SongFile>[].obs;
  // Index within queue
  RxInt queueIndex = (-1).obs;

  RxBool isPlaying = false.obs;
  RxBool isLoading = false.obs;
  Rx<Duration> position = Duration.zero.obs;
  Rx<Duration> duration = Duration.zero.obs;
  RxString error = ''.obs;
  RxString searchQuery = ''.obs;
  RxString queueSource = 'Library'.obs; // label shown in NowPlaying

  Rx<LoopMode> loopMode = LoopMode.none.obs;
  RxBool shuffleEnabled = false.obs;

  final List<int> _shuffleHistory = [];
  int _shuffleHistoryIndex = -1;

  @override
  void onInit() {
    super.onInit();
    player.positionStream.listen((p) => position.value = p);
    player.durationStream.listen((d) => duration.value = d ?? Duration.zero);
    player.playingStream.listen((p) => isPlaying.value = p);
    player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) _onTrackComplete();
    });
    loadSongs();
  }

  // ─── Library filter ───────────────────────────────────────
  void filterSongs(String query) {
    searchQuery.value = query;
    if (query.trim().isEmpty) {
      filteredSongs.assignAll(songs);
    } else {
      final q = query.toLowerCase();
      filteredSongs.assignAll(
        songs.where((s) => s.name.toLowerCase().contains(q)).toList(),
      );
    }
  }

  List<String> getSearchSuggestions(String query) {
    if (query.trim().length < 2) return [];
    final q = query.toLowerCase();
    return songs
        .where((s) => s.name.toLowerCase().contains(q))
        .map((s) => s.name)
        .take(6)
        .toList();
  }

  // ─── Load songs ───────────────────────────────────────────
  Future<void> loadSongs() async {
    isLoading.value = true;
    error.value = '';
    try {
      await _requestPermissions();
      final dirs = await _getMusicDirs();
      final found =
          await compute(_scanDirsIsolate, dirs.map((d) => d.path).toList());
      found.sort((a, b) => a[0].compareTo(b[0]));
      final mapped = found
          .map((e) => SongFile(path: e[1], name: e[0], ext: e[2]))
          .toList();
      songs.assignAll(mapped);
      filteredSongs.assignAll(mapped);
    } catch (e) {
      error.value = 'Could not load songs: $e';
    } finally {
      isLoading.value = false;
    }
  }

  // ─── Play from library (sets queue = filteredSongs) ───────
  Future<void> playSong(int indexInFiltered) async {
    if (indexInFiltered < 0 || indexInFiltered >= filteredSongs.length) return;
    // Set queue to current filtered view
    queue.assignAll(filteredSongs);
    queueSource.value =
        searchQuery.value.isEmpty ? 'Library' : 'Search results';
    queueIndex.value = indexInFiltered;
    _resetShuffleHistory(indexInFiltered);
    await _playCurrentQueueItem();
  }

  // ─── Play from playlist (sets queue = playlist songs) ─────
  Future<void> playFromPlaylist(
      List<SongFile> playlistSongs, int startIndex, String playlistName) async {
    if (startIndex < 0 || startIndex >= playlistSongs.length) return;
    queue.assignAll(playlistSongs);
    queueSource.value = playlistName;
    queueIndex.value = startIndex;
    _resetShuffleHistory(startIndex);
    await _playCurrentQueueItem();
  }

  // ─── Play next (insert after current) ────────────────────
  void addToPlayNext(SongFile song) {
    if (queue.isEmpty) {
      // Nothing playing — just start it
      queue.assignAll([song]);
      queueSource.value = 'Library';
      queueIndex.value = 0;
      _playCurrentQueueItem();
      return;
    }
    // Insert right after current position
    final insertAt = queueIndex.value + 1;
    final newQueue = List<SongFile>.from(queue);
    // Remove if already in queue ahead of current
    newQueue.removeWhere((s) => s.path == song.path);
    // Find new current index after removal
    final newCurrentIdx =
        newQueue.indexWhere((s) => s.path == currentSong?.path);
    final actualInsertAt = newCurrentIdx >= 0 ? newCurrentIdx + 1 : insertAt;
    newQueue.insert(actualInsertAt.clamp(0, newQueue.length), song);
    final currentPath = currentSong?.path;
    queue.assignAll(newQueue);
    if (currentPath != null) {
      queueIndex.value = newQueue.indexWhere((s) => s.path == currentPath);
    }
    Get.snackbar('Up Next', '"${song.name}" added to play next',
        backgroundColor: AppTheme.surface,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
        snackPosition: SnackPosition.BOTTOM);
  }

  // ─── Reorder queue ────────────────────────────────────────
  void reorderQueue(int oldIndex, int newIndex) {
    // Adjust for ReorderableListView quirk
    if (newIndex > oldIndex) newIndex--;
    final currentPath = currentSong?.path;
    final newQueue = List<SongFile>.from(queue);
    final item = newQueue.removeAt(oldIndex);
    newQueue.insert(newIndex, item);
    queue.assignAll(newQueue);
    // Keep queueIndex pointing at the same song
    if (currentPath != null) {
      queueIndex.value = newQueue.indexWhere((s) => s.path == currentPath);
    }
  }

  void removeFromQueue(int index) {
    if (index == queueIndex.value) return; // can't remove currently playing
    final currentPath = currentSong?.path;
    final newQueue = List<SongFile>.from(queue);
    newQueue.removeAt(index);
    queue.assignAll(newQueue);
    if (currentPath != null) {
      queueIndex.value = newQueue.indexWhere((s) => s.path == currentPath);
    }
  }

  // ─── Playback ─────────────────────────────────────────────
  Future<void> _playCurrentQueueItem() async {
    if (queueIndex.value < 0 || queueIndex.value >= queue.length) return;
    final song = queue[queueIndex.value];
    // Keep currentIndex in songs list in sync for library highlighting
    final realIdx = songs.indexWhere((s) => s.path == song.path);
    // We store in queueIndex, not currentIndex for queue-based playback
    try {
      await player.setFilePath(song.path);
      await player.play();
    } catch (e) {
      error.value = 'Cannot play: ${song.name}';
    }
  }

  void _onTrackComplete() {
    switch (loopMode.value) {
      case LoopMode.one:
        player.seek(Duration.zero);
        player.play();
        break;
      case LoopMode.all:
        playNext();
        break;
      case LoopMode.none:
        if (queueIndex.value < queue.length - 1) playNext();
        break;
    }
  }

  void playNext() {
    if (queue.isEmpty) return;
    if (shuffleEnabled.value) {
      if (_shuffleHistoryIndex < _shuffleHistory.length - 1) {
        _shuffleHistoryIndex++;
        queueIndex.value = _shuffleHistory[_shuffleHistoryIndex];
        _playCurrentQueueItem();
        return;
      }
      int next;
      final rng = DateTime.now().millisecondsSinceEpoch;
      next = rng % queue.length;
      if (queue.length > 1) {
        while (next == queueIndex.value) {
          next = (next + 1) % queue.length;
        }
      }
      _shuffleHistory.add(next);
      _shuffleHistoryIndex = _shuffleHistory.length - 1;
      queueIndex.value = next;
    } else {
      queueIndex.value = (queueIndex.value + 1) % queue.length;
    }
    _playCurrentQueueItem();
  }

  void playPrev() {
    if (queue.isEmpty) return;
    if (position.value.inSeconds > 3) {
      player.seek(Duration.zero);
      return;
    }
    if (shuffleEnabled.value && _shuffleHistoryIndex > 0) {
      _shuffleHistoryIndex--;
      queueIndex.value = _shuffleHistory[_shuffleHistoryIndex];
      _playCurrentQueueItem();
      return;
    }
    queueIndex.value =
        queueIndex.value <= 0 ? queue.length - 1 : queueIndex.value - 1;
    _playCurrentQueueItem();
  }

  void playByQueueIndex(int idx) {
    if (idx < 0 || idx >= queue.length) return;
    queueIndex.value = idx;
    _playCurrentQueueItem();
  }

  // Used by PlaylistDetail to play a song by path, respecting current queue context
  Future<void> playSongByPath(String path) async {
    final idx = filteredSongs.indexWhere((s) => s.path == path);
    if (idx >= 0) await playSong(idx);
  }

  void togglePlay() => player.playing ? player.pause() : player.play();

  void seek(double seconds) => player.seek(Duration(seconds: seconds.toInt()));

  void cycleLoopMode() {
    loopMode.value = switch (loopMode.value) {
      LoopMode.none => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.none,
    };
  }

  void toggleShuffle() {
    shuffleEnabled.value = !shuffleEnabled.value;
    if (shuffleEnabled.value) {
      _resetShuffleHistory(queueIndex.value);
    }
  }

  void _resetShuffleHistory(int startIdx) {
    _shuffleHistory.clear();
    _shuffleHistoryIndex = -1;
    if (startIdx >= 0) {
      _shuffleHistory.add(startIdx);
      _shuffleHistoryIndex = 0;
    }
  }

  SongFile? get currentSong =>
      queueIndex.value >= 0 && queueIndex.value < queue.length
          ? queue[queueIndex.value]
          : null;

  // For library row highlighting
  bool isCurrentSong(String path) => currentSong?.path == path;

  Future<void> _requestPermissions() async {
    await Permission.audio.request();
    await Permission.storage.request();
  }

  Future<List<Directory>> _getMusicDirs() async {
    final dirs = <Directory>[];
    try {
      final d =
          await getExternalStorageDirectories(type: StorageDirectory.music);
      if (d != null) dirs.addAll(d);
    } catch (_) {}
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        final parts = ext.path.split('/');
        final rootIdx = parts.indexOf('Android');
        if (rootIdx > 0) {
          final root = parts.sublist(0, rootIdx).join('/');
          dirs.add(Directory('$root/Music'));
          dirs.add(Directory('$root/Download'));
        }
      }
    } catch (_) {}
    try {
      final app = await getApplicationDocumentsDirectory();
      dirs.add(Directory('${app.path}/Music'));
    } catch (_) {}
    return dirs;
  }

  @override
  void onClose() {
    player.dispose();
    super.onClose();
  }
}

List<List<String>> _scanDirsIsolate(List<String> dirPaths) {
  final results = <List<String>>[];
  const supportedExts = {'.mp3', '.flac', '.m4a', '.aac', '.ogg', '.wav'};
  for (final dirPath in dirPaths) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) continue;
    try {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        // Skip empty/partial files — these are failed downloads
        if (entity.lengthSync() < 1024) continue;
        final lower = entity.path.toLowerCase();
        for (final ext in supportedExts) {
          if (lower.endsWith(ext)) {
            final name = entity.path.split('/').last.replaceAll(
                RegExp(r'\.(mp3|flac|m4a|aac|ogg|wav)$', caseSensitive: false),
                '');
            results.add([name, entity.path, ext.replaceFirst('.', '')]);
            break;
          }
        }
      }
    } catch (_) {}
  }
  return results;
}
