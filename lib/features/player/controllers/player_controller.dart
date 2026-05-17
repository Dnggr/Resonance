// lib/features/player/controllers/player_controller.dart
//
// CHANGE THIS SESSION:
//  [FIX-SHUFFLE-GETTERS] Added public getters `shuffleOrder` and `shufflePos`
//    so _QueueTab in now_playing_screen.dart can read the actual shuffle
//    sequence to display the queue in playback order instead of alphabetical.
//    These are read-only views of the private lists — no logic changed.

import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/audio_handler.dart';
import '../../../core/services/metadata_service.dart';
import '../../equalizer/controllers/equalizer_controller.dart';

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
  final AudioPlayer player;
  final ResonanceAudioHandler? _handler;

  PlayerController()
      : player = AudioPlayer(),
        _handler = null;

  PlayerController.withHandler(
    AudioPlayer sharedPlayer,
    ResonanceAudioHandler handler,
  )   : player = sharedPlayer,
        _handler = handler;

  RxList<SongFile> songs = <SongFile>[].obs;
  RxList<SongFile> filteredSongs = <SongFile>[].obs;
  RxList<SongFile> queue = <SongFile>[].obs;
  RxInt queueIndex = (-1).obs;

  RxBool isPlaying = false.obs;
  RxBool isLoading = false.obs;
  Rx<Duration> position = Duration.zero.obs;
  Rx<Duration> duration = Duration.zero.obs;
  RxString error = ''.obs;
  RxString searchQuery = ''.obs;
  RxString queueSource = 'Library'.obs;

  Rx<LoopMode> loopMode = LoopMode.none.obs;
  RxBool shuffleEnabled = false.obs;

  final List<int> _shuffleOrder = [];
  int _shufflePos = 0;

  // ── FIX-SHUFFLE-GETTERS: read-only access for queue display ──────────────
  // _QueueTab reads these to render the queue in actual shuffle playback order.
  List<int> get shuffleOrder => List.unmodifiable(_shuffleOrder);
  int get shufflePos => _shufflePos;

  DateTime _lastPositionUpdate = DateTime.now();
  StreamSubscription<ProcessingState>? _eqInitSub;
  Timer? _autoRefreshTimer;
  Timer? _searchDebounce;

  MetadataService? get _meta {
    try {
      return Get.find<MetadataService>();
    } catch (_) {
      return null;
    }
  }

  @override
  void onInit() {
    super.onInit();
    player.positionStream.listen((p) {
      final now = DateTime.now();
      if (now.difference(_lastPositionUpdate).inMilliseconds >= 250) {
        position.value = p;
        _lastPositionUpdate = now;
      }
    });
    player.durationStream.listen((d) => duration.value = d ?? Duration.zero);
    player.playingStream.listen((p) => isPlaying.value = p);

    player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) _onTrackComplete();
    });

    loadSongs();
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!isLoading.value && !isPlaying.value) {
        await _silentRefresh();
      }
    });
  }

  Future<void> _silentRefresh() async {
    try {
      final dirs = await _getMusicDirs();
      final found =
          await compute(_scanDirsIsolate, dirs.map((d) => d.path).toList());
      found.sort((a, b) => a[0].compareTo(b[0]));
      final mapped = found
          .map((e) => SongFile(path: e[1], name: e[0], ext: e[2]))
          .toList();

      if (mapped.length != songs.length ||
          !mapped.every((s) => songs.any((e) => e.path == s.path))) {
        songs.assignAll(mapped);
        if (searchQuery.value.trim().isEmpty) {
          filteredSongs.assignAll(mapped);
        } else {
          final q = searchQuery.value.toLowerCase();
          filteredSongs.assignAll(
              mapped.where((s) => s.name.toLowerCase().contains(q)).toList());
        }
      }
    } catch (e) {
      debugPrint('Silent refresh error (non-fatal): $e');
    }
  }

  void filterSongs(String query) {
    searchQuery.value = query;
    _searchDebounce?.cancel();

    if (query.trim().isEmpty) {
      filteredSongs.assignAll(songs);
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final q = query.toLowerCase();
      filteredSongs.assignAll(
        songs.where((s) => s.name.toLowerCase().contains(q)).toList(),
      );
    });
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

  Future<void> playSong(int indexInFiltered) async {
    if (indexInFiltered < 0 || indexInFiltered >= filteredSongs.length) return;
    final tappedSong = filteredSongs[indexInFiltered];

    final allSongs = List<SongFile>.from(songs);
    final startIdx = allSongs.indexWhere((s) => s.path == tappedSong.path);
    final safeStart = startIdx >= 0 ? startIdx : 0;

    queue.assignAll(allSongs);
    queueSource.value = searchQuery.value.isEmpty
        ? 'Library'
        : 'Library (from "${tappedSong.name}")';
    queueIndex.value = safeStart;
    _buildShuffleOrder(safeStart);
    await _playCurrentQueueItem();
  }

  Future<void> playFromPlaylist(
      List<SongFile> playlistSongs, int startIndex, String playlistName) async {
    if (playlistSongs.isEmpty) return;
    final safeStart = startIndex.clamp(0, playlistSongs.length - 1);
    queue.assignAll(playlistSongs);
    queueSource.value = playlistName;
    queueIndex.value = safeStart;
    _buildShuffleOrder(safeStart);
    await _playCurrentQueueItem();
  }

  void addToPlayNext(SongFile song) {
    if (queue.isEmpty) {
      queue.assignAll([song]);
      queueSource.value = 'Library';
      queueIndex.value = 0;
      _buildShuffleOrder(0);
      _playCurrentQueueItem();
      return;
    }
    final newQueue = List<SongFile>.from(queue);
    newQueue.removeWhere((s) => s.path == song.path);
    final newCurrentIdx =
        newQueue.indexWhere((s) => s.path == currentSong?.path);
    final actualInsertAt =
        newCurrentIdx >= 0 ? newCurrentIdx + 1 : queueIndex.value + 1;
    newQueue.insert(actualInsertAt.clamp(0, newQueue.length), song);
    final currentPath = currentSong?.path;
    queue.assignAll(newQueue);
    if (currentPath != null) {
      final newIdx = newQueue.indexWhere((s) => s.path == currentPath);
      queueIndex.value = newIdx;
      if (shuffleEnabled.value) _buildShuffleOrder(newIdx);
    }
    Get.snackbar('Up Next', '"${song.name}" added to play next',
        backgroundColor: AppTheme.surface,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
        snackPosition: SnackPosition.BOTTOM);
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final currentPath = currentSong?.path;
    final newQueue = List<SongFile>.from(queue);
    final item = newQueue.removeAt(oldIndex);
    newQueue.insert(newIndex, item);
    queue.assignAll(newQueue);
    if (currentPath != null) {
      final newIdx = newQueue.indexWhere((s) => s.path == currentPath);
      queueIndex.value = newIdx;
      if (shuffleEnabled.value) _buildShuffleOrder(newIdx);
    }
  }

  void removeFromQueue(int index) {
    if (index == queueIndex.value) return;
    final currentPath = currentSong?.path;
    final newQueue = List<SongFile>.from(queue);
    newQueue.removeAt(index);
    queue.assignAll(newQueue);
    if (currentPath != null) {
      final newIdx = newQueue.indexWhere((s) => s.path == currentPath);
      queueIndex.value = newIdx;
      if (shuffleEnabled.value) _buildShuffleOrder(newIdx);
    }
  }

  Future<void> _playCurrentQueueItem() async {
    if (queueIndex.value < 0 || queueIndex.value >= queue.length) return;
    final song = queue[queueIndex.value];

    await _eqInitSub?.cancel();
    _eqInitSub = null;

    try {
      final meta = _meta;
      final title = meta?.displayTitle(song.path, song.name) ?? song.name;
      final artist = meta?.displayArtist(song.path) ?? 'Unknown Artist';
      final album = meta?.displayAlbum(song.path) ?? song.ext.toUpperCase();
      final artPath = meta?.artImagePath(song.path);

      Uri? artUri;
      if (artPath != null && File(artPath).existsSync()) {
        artUri = Uri.file(artPath);
      }

      final item = MediaItem(
        id: song.path,
        title: title,
        artist: artist,
        album: album,
        artUri: artUri,
        duration: duration.value == Duration.zero ? null : duration.value,
      );

      if (_handler != null) {
        await _handler!.playFile(song.path, item);
      } else {
        await player.setFilePath(song.path);
        await player.play();
      }

      _scheduleEqInit();
    } catch (e) {
      error.value = 'Cannot play: ${song.name}';
      debugPrint('Playback error: $e');
    }
  }

  void _scheduleEqInit() {
    _eqInitSub?.cancel();
    _eqInitSub = null;

    if (player.processingState == ProcessingState.ready) {
      _initEqualizer();
      return;
    }

    _eqInitSub = player.processingStateStream
        .where((s) => s == ProcessingState.ready)
        .take(1)
        .listen((_) async {
      await _initEqualizer();
      _eqInitSub?.cancel();
      _eqInitSub = null;
    });
  }

  Future<void> _initEqualizer() async {
    try {
      final sessionId = await player.androidAudioSessionId;
      if (sessionId == null) return;
      if (!Get.isRegistered<EqualizerController>()) return;
      final eq = Get.find<EqualizerController>();
      await eq.init(sessionId);
    } catch (e) {
      debugPrint('EQ init error (non-fatal): $e');
    }
  }

  void refreshCurrentSongNotification() {
    if (_handler == null || currentSong == null) return;
    final song = currentSong!;
    final meta = _meta;
    final title = meta?.displayTitle(song.path, song.name) ?? song.name;
    final artist = meta?.displayArtist(song.path) ?? 'Unknown Artist';
    final album = meta?.displayAlbum(song.path) ?? song.ext.toUpperCase();
    final artPath = meta?.artImagePath(song.path);

    Uri? artUri;
    if (artPath != null && File(artPath).existsSync()) {
      artUri = Uri.file(artPath);
    }

    final item = MediaItem(
      id: song.path,
      title: title,
      artist: artist,
      album: album,
      artUri: artUri,
      duration: duration.value == Duration.zero ? null : duration.value,
    );

    _handler!.updateMediaItem(item);
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
        if (shuffleEnabled.value) {
          if (_shufflePos < _shuffleOrder.length - 1) {
            playNext();
          }
        } else {
          if (queueIndex.value < queue.length - 1) playNext();
        }
        break;
    }
  }

  void playNext() {
    if (queue.isEmpty) return;

    if (shuffleEnabled.value) {
      if (_shuffleOrder.isEmpty) _buildShuffleOrder(queueIndex.value);

      if (_shufflePos < _shuffleOrder.length - 1) {
        _shufflePos++;
      } else {
        _rebuildShuffleOrderFromScratch();
        _shufflePos = 0;
      }
      queueIndex.value = _shuffleOrder[_shufflePos];
    } else {
      if (loopMode.value == LoopMode.all) {
        queueIndex.value = (queueIndex.value + 1) % queue.length;
      } else {
        queueIndex.value = (queueIndex.value + 1).clamp(0, queue.length - 1);
      }
    }
    _playCurrentQueueItem();
  }

  void playPrev() {
    if (queue.isEmpty) return;
    if (position.value.inSeconds > 3) {
      player.seek(Duration.zero);
      return;
    }

    if (shuffleEnabled.value) {
      if (_shuffleOrder.isEmpty) _buildShuffleOrder(queueIndex.value);
      if (_shufflePos > 0) {
        _shufflePos--;
        queueIndex.value = _shuffleOrder[_shufflePos];
      } else {
        player.seek(Duration.zero);
        return;
      }
    } else {
      queueIndex.value =
          queueIndex.value <= 0 ? queue.length - 1 : queueIndex.value - 1;
    }
    _playCurrentQueueItem();
  }

  void playByQueueIndex(int idx) {
    if (idx < 0 || idx >= queue.length) return;
    queueIndex.value = idx;
    if (shuffleEnabled.value) {
      final posInOrder = _shuffleOrder.indexOf(idx);
      if (posInOrder >= 0) {
        _shufflePos = posInOrder;
      } else {
        _shuffleOrder.insert(_shufflePos + 1, idx);
        _shufflePos++;
      }
    }
    _playCurrentQueueItem();
  }

  Future<void> playSongByPath(String path) async {
    final idx = songs.indexWhere((s) => s.path == path);
    if (idx >= 0) {
      queue.assignAll(List<SongFile>.from(songs));
      queueSource.value = 'Library';
      queueIndex.value = idx;
      _buildShuffleOrder(idx);
      await _playCurrentQueueItem();
    }
  }

  void togglePlay() {
    if (_handler != null) {
      player.playing ? _handler!.pause() : _handler!.play();
    } else {
      player.playing ? player.pause() : player.play();
    }
  }

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
      _buildShuffleOrder(queueIndex.value);
    }
  }

  void _buildShuffleOrder(int currentIdx) {
    _shuffleOrder.clear();
    _shufflePos = 0;

    if (queue.isEmpty) return;

    final others = List<int>.generate(queue.length, (i) => i)
      ..remove(currentIdx);

    for (int i = others.length - 1; i > 0; i--) {
      final j =
          (DateTime.now().microsecondsSinceEpoch ^ (i * 2654435761)) % (i + 1);
      final tmp = others[i];
      others[i] = others[j.abs()];
      others[j.abs()] = tmp;
    }

    _shuffleOrder.add(currentIdx);
    _shuffleOrder.addAll(others);
    _shufflePos = 0;
  }

  void _rebuildShuffleOrderFromScratch() {
    final lastPlayed = _shuffleOrder.isNotEmpty
        ? _shuffleOrder.last
        : (queueIndex.value >= 0 ? queueIndex.value : 0);

    final indices = List<int>.generate(queue.length, (i) => i)
      ..remove(lastPlayed);

    for (int i = indices.length - 1; i > 0; i--) {
      final j =
          (DateTime.now().microsecondsSinceEpoch ^ (i * 2654435761)) % (i + 1);
      final tmp = indices[i];
      indices[i] = indices[j.abs()];
      indices[j.abs()] = tmp;
    }

    _shuffleOrder.clear();
    _shuffleOrder.addAll(indices);
    _shuffleOrder.add(lastPlayed);
    _shufflePos = 0;
  }

  SongFile? get currentSong =>
      queueIndex.value >= 0 && queueIndex.value < queue.length
          ? queue[queueIndex.value]
          : null;

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
    _eqInitSub?.cancel();
    _autoRefreshTimer?.cancel();
    _searchDebounce?.cancel();
    if (_handler == null) player.dispose();
    super.onClose();
  }
}

// ─── Format filter: mp3, m4a, flac only ─────────────────────────────────────

List<List<String>> _scanDirsIsolate(List<String> dirPaths) {
  final results = <List<String>>[];
  const supportedExts = {'.mp3', '.flac', '.m4a'};
  for (final dirPath in dirPaths) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) continue;
    try {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (entity.lengthSync() < 1024) continue;
        final lower = entity.path.toLowerCase();
        for (final ext in supportedExts) {
          if (lower.endsWith(ext)) {
            final name = entity.path.split('/').last.replaceAll(
                RegExp(r'\.(mp3|flac|m4a)$', caseSensitive: false), '');
            results.add([name, entity.path, ext.replaceFirst('.', '')]);
            break;
          }
        }
      }
    } catch (_) {}
  }
  return results;
}
