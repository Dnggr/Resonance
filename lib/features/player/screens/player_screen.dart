import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme/app_theme.dart';

class SongFile {
  final String path;
  final String name;
  final String ext;
  SongFile({required this.path, required this.name, required this.ext});
}

class PlayerController extends GetxController {
  final AudioPlayer player = AudioPlayer();
  RxList<SongFile> songs = <SongFile>[].obs;
  RxInt currentIndex = (-1).obs;
  RxBool isPlaying = false.obs;
  RxBool isLoading = false.obs;
  Rx<Duration> position = Duration.zero.obs;
  Rx<Duration> duration = Duration.zero.obs;
  RxString error = ''.obs;

  @override
  void onInit() {
    super.onInit();
    player.positionStream.listen((p) => position.value = p);
    player.durationStream.listen((d) => duration.value = d ?? Duration.zero);
    player.playingStream.listen((p) => isPlaying.value = p);
    player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) _playNext();
    });
    loadSongs();
  }

  Future<void> loadSongs() async {
    isLoading.value = true;
    error.value = '';
    final found = <SongFile>[];

    try {
      await _requestPermissions();

      // Scan all possible music directories
      final dirs = await _getMusicDirs();
      for (final dir in dirs) {
        await _scanDir(dir, found);
      }

      // Sort alphabetically
      found.sort((a, b) => a.name.compareTo(b.name));
      songs.assignAll(found);
    } catch (e) {
      error.value = 'Could not load songs: $e';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _scanDir(Directory dir, List<SongFile> found) async {
    if (!await dir.exists()) return;
    final supportedExts = {
      '.mp3',
      '.flac',
      '.m4a',
      '.aac',
      '.ogg',
      '.wav',
      '.mp4'
    };
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          final lower = entity.path.toLowerCase();
          for (final ext in supportedExts) {
            if (lower.endsWith(ext)) {
              final name = entity.path.split('/').last.replaceAll(
                  RegExp(r'\.(mp3|flac|m4a|aac|ogg|wav|mp4)$',
                      caseSensitive: false),
                  '');
              found.add(SongFile(
                  path: entity.path,
                  name: name,
                  ext: ext.replaceFirst('.', '')));
              break;
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<List<Directory>> _getMusicDirs() async {
    final dirs = <Directory>[];

    // 1. App's own Music folder (from downloader)
    try {
      final appDirs =
          await getExternalStorageDirectories(type: StorageDirectory.music);
      if (appDirs != null) dirs.addAll(appDirs);
    } catch (_) {}

    // 2. Standard Music folder
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        // Navigate to /storage/emulated/0/Music
        final parts = ext.path.split('/');
        final rootIdx = parts.indexOf('Android');
        if (rootIdx > 0) {
          final root = parts.sublist(0, rootIdx).join('/');
          dirs.add(Directory('$root/Music'));
          dirs.add(Directory('$root/Download'));
        }
      }
    } catch (_) {}

    // 3. App documents fallback
    try {
      final app = await getApplicationDocumentsDirectory();
      dirs.add(Directory('${app.path}/Music'));
    } catch (_) {}

    return dirs;
  }

  Future<void> _requestPermissions() async {
    await Permission.audio.request();
    await Permission.storage.request();
  }

  Future<void> playSong(int index) async {
    if (index < 0 || index >= songs.length) return;
    currentIndex.value = index;
    try {
      await player.setFilePath(songs[index].path);
      await player.play();
    } catch (e) {
      error.value = 'Cannot play: ${songs[index].name}';
    }
  }

  void _playNext() {
    final next = (currentIndex.value + 1) % songs.length;
    playSong(next);
  }

  void playNext() => _playNext();

  void playPrev() {
    final prev =
        currentIndex.value <= 0 ? songs.length - 1 : currentIndex.value - 1;
    playSong(prev);
  }

  void togglePlay() {
    if (player.playing) {
      player.pause();
    } else {
      player.play();
    }
  }

  void seek(double value) {
    player.seek(Duration(seconds: value.toInt()));
  }

  @override
  void onClose() {
    player.dispose();
    super.onClose();
  }
}

// ─── Player Screen ────────────────────────────────────────────
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(PlayerController());

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(ctrl: ctrl),
            Expanded(child: _SongList(ctrl: ctrl)),
            _MiniPlayer(ctrl: ctrl),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final PlayerController ctrl;
  const _Header({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Library',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5)),
              Obx(() => Text('${ctrl.songs.length} songs',
                  style: const TextStyle(color: Colors.white38, fontSize: 13))),
            ]),
          ),
          IconButton(
            onPressed: ctrl.loadSongs,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
            tooltip: 'Refresh library',
          ),
        ],
      ),
    );
  }
}

class _SongList extends StatelessWidget {
  final PlayerController ctrl;
  const _SongList({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.isLoading.value) {
        return const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: AppTheme.primary),
            SizedBox(height: 16),
            Text('Scanning music library...',
                style: TextStyle(color: Colors.white38)),
          ]),
        );
      }

      if (ctrl.songs.isEmpty) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.library_music_rounded,
                size: 64, color: Colors.white12),
            const SizedBox(height: 12),
            const Text('No music found',
                style: TextStyle(color: Colors.white54, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('Download songs or copy to Music folder',
                style: TextStyle(color: Colors.white30, fontSize: 13)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: ctrl.loadSongs,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ]),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: ctrl.songs.length,
        itemBuilder: (_, i) {
          final song = ctrl.songs[i];
          return Obx(() {
            final isCurrent = ctrl.currentIndex.value == i;
            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? AppTheme.primary.withOpacity(0.2)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: isCurrent
                      ? Border.all(color: AppTheme.primary.withOpacity(0.5))
                      : null,
                ),
                child: isCurrent && ctrl.isPlaying.value
                    ? const Icon(Icons.equalizer_rounded,
                        color: AppTheme.primary, size: 20)
                    : Icon(_iconForExt(song.ext),
                        color: isCurrent ? AppTheme.primary : Colors.white30,
                        size: 20),
              ),
              title: Text(
                song.name,
                style: TextStyle(
                  color: isCurrent ? AppTheme.primary : Colors.white,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                song.ext.toUpperCase(),
                style: const TextStyle(color: Colors.white30, fontSize: 11),
              ),
              onTap: () => ctrl.playSong(i),
              trailing: isCurrent
                  ? IconButton(
                      icon: Icon(
                        ctrl.isPlaying.value
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: AppTheme.primary,
                      ),
                      onPressed: ctrl.togglePlay,
                    )
                  : null,
            );
          });
        },
      );
    });
  }

  IconData _iconForExt(String ext) {
    return switch (ext.toLowerCase()) {
      'mp3' => Icons.music_note_rounded,
      'flac' => Icons.high_quality_rounded,
      'm4a' || 'aac' => Icons.audiotrack_rounded,
      'wav' => Icons.graphic_eq_rounded,
      'mp4' => Icons.video_file_rounded,
      _ => Icons.audio_file_rounded,
    };
  }
}

// ─── Mini Player Bar ──────────────────────────────────────────
class _MiniPlayer extends StatelessWidget {
  final PlayerController ctrl;
  const _MiniPlayer({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.currentIndex.value < 0) return const SizedBox.shrink();
      final song = ctrl.songs[ctrl.currentIndex.value];
      final dur = ctrl.duration.value.inSeconds.toDouble();
      final pos = ctrl.position.value.inSeconds.toDouble();

      return Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
                color: AppTheme.primary.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.music_note_rounded,
                    color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(_fmt(ctrl.position.value),
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                    ]),
              ),
              IconButton(
                  icon: const Icon(Icons.skip_previous_rounded,
                      color: Colors.white70),
                  onPressed: ctrl.playPrev,
                  iconSize: 22),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(12)),
                child: IconButton(
                  icon: Icon(
                    ctrl.isPlaying.value
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                  ),
                  onPressed: ctrl.togglePlay,
                  iconSize: 22,
                  padding: EdgeInsets.zero,
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.skip_next_rounded,
                      color: Colors.white70),
                  onPressed: ctrl.playNext,
                  iconSize: 22),
            ]),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: AppTheme.primary,
                inactiveTrackColor: Colors.white12,
                thumbColor: AppTheme.primary,
              ),
              child: Slider(
                value: pos.clamp(0, dur <= 0 ? 1 : dur),
                max: dur <= 0 ? 1 : dur,
                onChanged: dur > 0 ? ctrl.seek : null,
              ),
            ),
          ],
        ),
      );
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
