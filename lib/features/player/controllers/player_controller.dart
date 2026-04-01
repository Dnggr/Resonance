import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class SongFile {
  final String path;
  final String name;
  final String ext;
  const SongFile({required this.path, required this.name, required this.ext});
}

enum LoopMode { none, one, all }

class PlayerController extends GetxController {
  final AudioPlayer player = AudioPlayer();

  RxList<SongFile> songs = <SongFile>[].obs;
  RxList<SongFile> filteredSongs = <SongFile>[].obs;
  RxInt currentIndex = (-1).obs;
  RxBool isPlaying = false.obs;
  RxBool isLoading = false.obs;
  Rx<Duration> position = Duration.zero.obs;
  Rx<Duration> duration = Duration.zero.obs;
  RxString error = ''.obs;
  RxString searchQuery = ''.obs;

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
          .map((e) => SongFile(
                path: e[1],
                name: e[0],
                ext: e[2],
              ))
          .toList();
      songs.assignAll(mapped);
      filteredSongs.assignAll(mapped);
    } catch (e) {
      error.value = 'Could not load songs: $e';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> playSong(int indexInFiltered) async {
    if (indexInFiltered < 0 || indexInFiltered >= filteredSongs.length) return;
    final song = filteredSongs[indexInFiltered];
    final realIdx = songs.indexWhere((s) => s.path == song.path);
    currentIndex.value = realIdx;

    if (shuffleEnabled.value) {
      _shuffleHistory.add(realIdx);
      _shuffleHistoryIndex = _shuffleHistory.length - 1;
    }

    try {
      await player.setFilePath(song.path);
      await player.play();
    } catch (e) {
      error.value = 'Cannot play: ${song.name}';
    }
  }

  Future<void> playSongByPath(String path) async {
    final idx = filteredSongs.indexWhere((s) => s.path == path);
    if (idx >= 0) await playSong(idx);
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
        if (_hasNext()) playNext();
        break;
    }
  }

  bool _hasNext() {
    if (shuffleEnabled.value) return true;
    return currentIndex.value < songs.length - 1;
  }

  void playNext() {
    if (songs.isEmpty) return;
    if (shuffleEnabled.value) {
      if (_shuffleHistoryIndex < _shuffleHistory.length - 1) {
        _shuffleHistoryIndex++;
        final idx = _shuffleHistory[_shuffleHistoryIndex];
        playByRealIndex(idx);
        return;
      }
      int next;
      do {
        next = (songs.length *
                (DateTime.now().millisecondsSinceEpoch % 1000 / 1000))
            .floor();
      } while (next == currentIndex.value && songs.length > 1);
      next = next % songs.length;
      _shuffleHistory.add(next);
      _shuffleHistoryIndex = _shuffleHistory.length - 1;
      playByRealIndex(next);
    } else {
      final next = (currentIndex.value + 1) % songs.length;
      playByRealIndex(next);
    }
  }

  void playPrev() {
    if (songs.isEmpty) return;
    if (position.value.inSeconds > 3) {
      player.seek(Duration.zero);
      return;
    }
    if (shuffleEnabled.value && _shuffleHistoryIndex > 0) {
      _shuffleHistoryIndex--;
      playByRealIndex(_shuffleHistory[_shuffleHistoryIndex]);
      return;
    }
    final prev =
        currentIndex.value <= 0 ? songs.length - 1 : currentIndex.value - 1;
    playByRealIndex(prev);
  }

  // Public — can be called from NowPlayingScreen queue list
  void playByRealIndex(int realIdx) async {
    if (realIdx < 0 || realIdx >= songs.length) return;
    currentIndex.value = realIdx;
    try {
      await player.setFilePath(songs[realIdx].path);
      await player.play();
    } catch (_) {}
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
      _shuffleHistory.clear();
      _shuffleHistoryIndex = -1;
      if (currentIndex.value >= 0) {
        _shuffleHistory.add(currentIndex.value);
        _shuffleHistoryIndex = 0;
      }
    }
  }

  SongFile? get currentSong =>
      currentIndex.value >= 0 && currentIndex.value < songs.length
          ? songs[currentIndex.value]
          : null;

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
        if (entity is File) {
          final lower = entity.path.toLowerCase();
          for (final ext in supportedExts) {
            if (lower.endsWith(ext)) {
              final name = entity.path.split('/').last.replaceAll(
                  RegExp(r'\.(mp3|flac|m4a|aac|ogg|wav)$',
                      caseSensitive: false),
                  '');
              results.add([name, entity.path, ext.replaceFirst('.', '')]);
              break;
            }
          }
        }
      }
    } catch (_) {}
  }
  return results;
}
