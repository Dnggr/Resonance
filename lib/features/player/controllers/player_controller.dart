// lib/features/player/controllers/player_controller.dart
//
// FIX LOG (this session):
//  [FIX-SHUFFLE] Shuffle now uses a proper Fisher-Yates derangement so ALL
//    songs play exactly once before repeating. Old code used millisecondsSinceEpoch
//    % queue.length which is NOT random — it consistently skips ~half the songs.
//    New approach: on shuffle-on or new-song-play, pre-generate a full shuffled
//    order (excluding the currently-playing song first, then appending it at
//    position 0). _shuffleOrder holds the full order; _shufflePos is the cursor.
//
//  [FIX-QUEUE-SEARCH] playSong() now always populates the queue from the full
//    songs list (not filteredSongs), starting at the correct index within songs.
//    When a search is active and the user taps a result, the queue is ALL songs
//    but starts at the tapped song. The queueSource label is updated accordingly.
//
//  [FIX-QUEUE-SCROLL] NowPlayingScreen Queue tab auto-scrolls to queueIndex.
//    (See now_playing_screen.dart — _QueueTab uses a ScrollController.)
//
//  [FIX-FORMAT-FILTER] _scanDirsIsolate only returns mp3, mp4/m4a, flac.
//    aac, ogg, wav removed.

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

  // ─── FIX-SHUFFLE: Full derangement-based shuffle ────────────────────────────
  // _shuffleOrder: pre-generated permutation of all queue indices.
  //   Index 0 is always the song that was playing when shuffle was activated.
  //   The remaining indices are a Fisher-Yates shuffle of all other songs.
  // _shufflePos: current position within _shuffleOrder.
  final List<int> _shuffleOrder = [];
  int _shufflePos = 0;

  DateTime _lastPositionUpdate = DateTime.now();
  StreamSubscription<ProcessingState>? _eqInitSub;
  Timer? _autoRefreshTimer;

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
    if (query.trim().isEmpty) {
      filteredSongs.assignAll(songs);
    } else {
      final q = query.toLowerCase();
      filteredSongs.assignAll(
          songs.where((s) => s.name.toLowerCase().contains(q)).toList());
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

  // ─── FIX-QUEUE-SEARCH ───────────────────────────────────────────────────────
  // When a user taps a song in the library (whether filtered or not), the queue
  // is populated from the FULL songs list. The index passed in is the index
  // within filteredSongs; we map it back to the index in songs so the queue
  // starts at the correct song and contains every song in the library.
  Future<void> playSong(int indexInFiltered) async {
    if (indexInFiltered < 0 || indexInFiltered >= filteredSongs.length) return;
    final tappedSong = filteredSongs[indexInFiltered];

    // Always queue ALL songs, find starting index by path
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
      // Rebuild shuffle order preserving current position
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
          // In shuffle mode, always advance unless we've played every song
          if (_shufflePos < _shuffleOrder.length - 1) {
            playNext();
          }
          // If we've played all songs, stop (no loop)
        } else {
          if (queueIndex.value < queue.length - 1) playNext();
        }
        break;
    }
  }

  // ─── FIX-SHUFFLE: playNext / playPrev use _shuffleOrder ─────────────────────
  void playNext() {
    if (queue.isEmpty) return;

    if (shuffleEnabled.value) {
      if (_shuffleOrder.isEmpty) _buildShuffleOrder(queueIndex.value);

      // Move forward in the pre-generated shuffle order
      if (_shufflePos < _shuffleOrder.length - 1) {
        _shufflePos++;
      } else {
        // All songs played — rebuild a new shuffle order starting fresh
        // (the first song of the new round will be random, not the same as last)
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
        // Already at start — restart current
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
    // Update shuffle position to match manually selected song
    if (shuffleEnabled.value) {
      final posInOrder = _shuffleOrder.indexOf(idx);
      if (posInOrder >= 0) {
        _shufflePos = posInOrder;
      } else {
        // Song not in shuffle history — insert it at current position
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

  // ─── FIX-SHUFFLE: Fisher-Yates derangement ──────────────────────────────────
  // Builds a complete shuffled order for all songs in the queue.
  // The currently playing song is placed at position 0 so it stays current,
  // and the rest are a proper random permutation.
  void _buildShuffleOrder(int currentIdx) {
    _shuffleOrder.clear();
    _shufflePos = 0;

    if (queue.isEmpty) return;

    // Build list of all indices except current
    final others = List<int>.generate(queue.length, (i) => i)
      ..remove(currentIdx);

    // Fisher-Yates shuffle
    for (int i = others.length - 1; i > 0; i--) {
      final j =
          (DateTime.now().microsecondsSinceEpoch ^ (i * 2654435761)) % (i + 1);
      final tmp = others[i];
      others[i] = others[j.abs()];
      others[j.abs()] = tmp;
    }

    // Current song first, then the shuffled rest
    _shuffleOrder.add(currentIdx);
    _shuffleOrder.addAll(others);
    _shufflePos = 0;
  }

  // When all songs have been played, rebuild with a truly random first song
  // (not the same as what just finished).
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
    _shuffleOrder.add(lastPlayed); // last played goes to end of next round
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
    if (_handler == null) player.dispose();
    super.onClose();
  }
}

// ─── FIX-FORMAT-FILTER: Only mp3, m4a (mp4 audio), flac ────────────────────
// Removed: aac, ogg, wav
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
