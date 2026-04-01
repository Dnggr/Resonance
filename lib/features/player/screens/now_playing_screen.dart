import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/player_controller.dart';
import '../../playlist/controllers/playlist_controller.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<PlayerController>();
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: Colors.white, size: 32),
          onPressed: () => Get.back(),
        ),
        title: const Text('Now Playing',
            style: TextStyle(color: Colors.white70, fontSize: 14)),
        centerTitle: true,
        actions: [
          Obx(() => ctrl.currentSong != null
              ? IconButton(
                  icon: const Icon(Icons.playlist_add_rounded,
                      color: Colors.white54),
                  onPressed: () =>
                      _showAddToPlaylist(context, ctrl.currentSong!.path),
                )
              : const SizedBox.shrink()),
        ],
      ),
      body: Obx(() {
        if (ctrl.currentSong == null) {
          return const Center(
              child: Text('Nothing playing',
                  style: TextStyle(color: Colors.white38)));
        }
        return Column(
          children: [
            const Spacer(),
            _AlbumArt(song: ctrl.currentSong!),
            const SizedBox(height: 32),
            _SongInfo(ctrl: ctrl),
            const SizedBox(height: 24),
            _SeekBar(ctrl: ctrl),
            const SizedBox(height: 16),
            _Controls(ctrl: ctrl),
            const SizedBox(height: 24),
            _QueueList(ctrl: ctrl),
          ],
        );
      }),
    );
  }

  void _showAddToPlaylist(BuildContext context, String songPath) {
    final plCtrl = Get.find<PlaylistController>();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Obx(() {
        return Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Add to playlist',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          const SizedBox(height: 8),
          if (plCtrl.playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No playlists yet. Create one from the Library.',
                  style: TextStyle(color: Colors.white38)),
            )
          else
            ...plCtrl.playlists.map((pl) => ListTile(
                  leading: const Icon(Icons.playlist_play_rounded,
                      color: AppTheme.primary),
                  title: Text(pl.name,
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text('${pl.songPaths.length} songs',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 12)),
                  onTap: () {
                    plCtrl.addSongToPlaylist(pl.id, songPath);
                    Get.back();
                    Get.snackbar('Added', 'Song added to ${pl.name}',
                        backgroundColor: AppTheme.surface,
                        colorText: Colors.white,
                        duration: const Duration(seconds: 2));
                  },
                )),
          const SizedBox(height: 16),
        ]);
      }),
    );
  }
}

class _AlbumArt extends StatelessWidget {
  final SongFile song;
  const _AlbumArt({required this.song});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 220,
      margin: const EdgeInsets.symmetric(horizontal: 40),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
              color: AppTheme.primary.withOpacity(0.2),
              blurRadius: 40,
              offset: const Offset(0, 8))
        ],
      ),
      child: const Center(
        child:
            Icon(Icons.music_note_rounded, color: AppTheme.primary, size: 80),
      ),
    );
  }
}

class _SongInfo extends StatelessWidget {
  final PlayerController ctrl;
  const _SongInfo({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(children: [
        Obx(() => Text(
              ctrl.currentSong?.name ?? '',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )),
        const SizedBox(height: 4),
        Obx(() => Text(ctrl.currentSong?.ext.toUpperCase() ?? '',
            style: const TextStyle(color: Colors.white38, fontSize: 13))),
      ]),
    );
  }
}

class _SeekBar extends StatelessWidget {
  final PlayerController ctrl;
  const _SeekBar({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final dur = ctrl.duration.value.inSeconds.toDouble();
      final pos = ctrl.position.value.inSeconds.toDouble();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(ctrl.position.value),
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 12)),
                Text(_fmt(ctrl.duration.value),
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
        ]),
      );
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _Controls extends StatelessWidget {
  final PlayerController ctrl;
  const _Controls({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Shuffle
              IconButton(
                icon: Icon(Icons.shuffle_rounded,
                    color: ctrl.shuffleEnabled.value
                        ? AppTheme.primary
                        : Colors.white38,
                    size: 22),
                onPressed: ctrl.toggleShuffle,
              ),
              // Prev
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded,
                    color: Colors.white, size: 32),
                onPressed: ctrl.playPrev,
              ),
              // Play/Pause — big center button
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: AppTheme.primary.withOpacity(0.4),
                          blurRadius: 20)
                    ]),
                child: IconButton(
                  icon: Icon(
                      ctrl.isPlaying.value
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 32),
                  onPressed: ctrl.togglePlay,
                ),
              ),
              // Next
              IconButton(
                icon: const Icon(Icons.skip_next_rounded,
                    color: Colors.white, size: 32),
                onPressed: ctrl.playNext,
              ),
              // Loop
              IconButton(
                icon: Icon(
                    ctrl.loopMode.value == LoopMode.one
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                    color: ctrl.loopMode.value != LoopMode.none
                        ? AppTheme.primary
                        : Colors.white38,
                    size: 22),
                onPressed: ctrl.cycleLoopMode,
              ),
            ],
          ),
        ));
  }
}

// ─── Queue list below controls ────────────────────────────────
class _QueueList extends StatelessWidget {
  final PlayerController ctrl;
  const _QueueList({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.songs.isEmpty) return const SizedBox.shrink();
      final currentIdx = ctrl.currentIndex.value;
      // Show up to 5 upcoming songs
      final upcoming = <SongFile>[];
      for (int i = 1; i <= 5; i++) {
        final idx = (currentIdx + i) % ctrl.songs.length;
        if (idx != currentIdx) upcoming.add(ctrl.songs[idx]);
      }
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Up next',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: upcoming.length,
                itemBuilder: (_, i) {
                  final song = upcoming[i];
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    leading: Icon(_iconForExt(song.ext),
                        color: Colors.white24, size: 16),
                    title: Text(song.name,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    onTap: () {
                      final idx = ctrl.songs.indexOf(song);
                      ctrl.playByRealIndex(idx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );
    });
  }

  IconData _iconForExt(String ext) => switch (ext.toLowerCase()) {
        'mp3' => Icons.music_note_rounded,
        'flac' => Icons.high_quality_rounded,
        _ => Icons.audiotrack_rounded,
      };
}
