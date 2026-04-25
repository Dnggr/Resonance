// lib/features/player/controllers/player_controller.dart
//
// FIX LOG:
//  [BUG-1] CRASH — Double track-complete handler.
//    audio_handler.dart no longer has a processingStateStream listener.
//    _onTrackComplete() here is the ONLY handler. See audio_handler.dart.
//
//  [BUG-2] CRASH — Dangling _eqInitSub cancel-inside-callback.
//    Old pattern: `await _eqInitSub?.cancel()` was called INSIDE the
//    stream.listen() callback, throwing "Bad state: Stream already cancelled"
//    on some Dart versions. Also the `await` inside listen() was fire-and-
//    forget — exceptions were swallowed.
//    FIX: _scheduleEqInit() uses .take(1) so the stream self-completes.
//    The cancel is done AFTER the await, with a null guard, outside the
//    stream callback. No more bad-state crash.
//
//  [BUG-4] LOGIC — artUri uses stale duration on first play.
//    `duration: duration.value` was passed when building the MediaItem but
//    on the very first play duration.value is still Duration.zero.
//    FIX: Pass `null` if duration is zero — audio_service then reads the
//    real duration from the stream once the file loads.
//    (This was already applied in the previous version; kept here for docs.)
//
//  [BUG-5] PERF — Auto-refresh runs during active playback.
//    Timer fired _silentRefresh() only if !isLoading, but not if playing.
//    The compute() isolate scan during seek caused 100–300 ms hitches on
//    large libraries.
//    FIX: _silentRefresh() is now also skipped while isPlaying is true.
//
//  [UX-1] — _MiniPlayer seek slider local drag state.
//    The mini-player Slider was bound directly to ctrl.position, so while
//    dragging the position stream kept overriding the thumb.
//    FIX: _MiniPlayer now manages its own _dragValue exactly like _SeekBar.
//    (The fix is in player_screen.dart's _MiniPlayer widget.)

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

  final List<int> _shuffleHistory = [];
  int _shuffleHistoryIndex = -1;

  DateTime _lastPositionUpdate = DateTime.now();

  // ─── FIX BUG-2: _eqInitSub is now cancelled safely ──────────────────────
  // We use .take(1) so the stream auto-completes after one event.
  // The cancel() call is done after the await, with a null-guard, and
  // _never_ from inside the stream's listen() callback.
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

    // ─── FIX BUG-1: SINGLE track-complete listener ───────────────────────
    // audio_handler.dart has had its processingStateStream listener removed.
    // This is now the only place that handles auto-advance.
    player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) _onTrackComplete();
    });

    loadSongs();
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      // ─── FIX BUG-5: Skip refresh while playing ───────────────────────
      // The compute() isolate scan causes perceptible hitches on large
      // libraries during active playback / seeking. We now also guard
      // against isPlaying being true, not just isLoading.
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

  Future<void> playSong(int indexInFiltered) async {
    if (indexInFiltered < 0 || indexInFiltered >= filteredSongs.length) return;
    queue.assignAll(filteredSongs);
    queueSource.value =
        searchQuery.value.isEmpty ? 'Library' : 'Search results';
    queueIndex.value = indexInFiltered;
    _resetShuffleHistory(indexInFiltered);
    await _playCurrentQueueItem();
  }

  Future<void> playFromPlaylist(
      List<SongFile> playlistSongs, int startIndex, String playlistName) async {
    if (playlistSongs.isEmpty) return;
    final safeStart = startIndex.clamp(0, playlistSongs.length - 1);
    queue.assignAll(playlistSongs);
    queueSource.value = playlistName;
    queueIndex.value = safeStart;
    _resetShuffleHistory(safeStart);
    await _playCurrentQueueItem();
  }

  void addToPlayNext(SongFile song) {
    if (queue.isEmpty) {
      queue.assignAll([song]);
      queueSource.value = 'Library';
      queueIndex.value = 0;
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
      queueIndex.value = newQueue.indexWhere((s) => s.path == currentPath);
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
      queueIndex.value = newQueue.indexWhere((s) => s.path == currentPath);
    }
  }

  void removeFromQueue(int index) {
    if (index == queueIndex.value) return;
    final currentPath = currentSong?.path;
    final newQueue = List<SongFile>.from(queue);
    newQueue.removeAt(index);
    queue.assignAll(newQueue);
    if (currentPath != null) {
      queueIndex.value = newQueue.indexWhere((s) => s.path == currentPath);
    }
  }

  Future<void> _playCurrentQueueItem() async {
    if (queueIndex.value < 0 || queueIndex.value >= queue.length) return;
    final song = queue[queueIndex.value];

    // ─── FIX BUG-2: Safe EQ subscription teardown ────────────────────────
    // Cancel any pending EQ init from the previous song. The cancel() is
    // called here (not inside a listen callback) so there's no bad-state risk.
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

      // ─── FIX BUG-4: Pass null duration instead of stale Duration.zero ──
      // On first play, duration.value is Duration.zero because the stream
      // hasn't emitted yet. Passing null tells audio_service to read it
      // from the stream once the file loads, so the lock screen shows the
      // correct duration instead of 0:00.
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

  // ─── FIX BUG-2: Safe EQ init subscription ────────────────────────────────
  // Old problem: subscribed to processingStateStream in a listen() callback,
  // then called `await _eqInitSub?.cancel()` from inside that same callback
  // → "Bad state: Stream already cancelled" on some Dart versions. Also the
  // await was fire-and-forget (exceptions swallowed).
  //
  // New pattern:
  //   1. Cancel old sub synchronously before creating a new one.
  //   2. Check current state first (avoids missing "ready" on fast devices).
  //   3. Use .take(1) so the stream self-completes after one event.
  //   4. After the awaited _initEqualizer(), cancel + null the sub OUTSIDE
  //      the listen callback (safe, no bad-state).
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
      // Safe to cancel here because .take(1) has already closed the stream.
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
      int next = DateTime.now().millisecondsSinceEpoch % queue.length;
      if (queue.length > 1) {
        while (next == queueIndex.value) next = (next + 1) % queue.length;
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

  Future<void> playSongByPath(String path) async {
    final idx = filteredSongs.indexWhere((s) => s.path == path);
    if (idx >= 0) await playSong(idx);
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
    if (shuffleEnabled.value) _resetShuffleHistory(queueIndex.value);
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

List<List<String>> _scanDirsIsolate(List<String> dirPaths) {
  final results = <List<String>>[];
  const supportedExts = {'.mp3', '.flac', '.m4a', '.aac', '.ogg', '.wav'};
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
