// lib/features/player/screens/now_playing_screen.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/player_controller.dart';
import '../../playlist/controllers/playlist_controller.dart';
import '../../equalizer/screens/equalizer_screen.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});
  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<PlayerController>();
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // ── FIX: Only ONE leading icon (back button auto-added by Flutter) ──
        // Previously there were TWO equalizer buttons: one in leading, one in actions.
        // Now: leading = back button (auto), actions = EQ + playlist add.
        actions: [
          // ── Equalizer button (single, in actions) ──────────────────────
          IconButton(
            icon: const Icon(Icons.equalizer_rounded, color: Colors.white54),
            tooltip: 'Equalizer & Amplifier',
            onPressed: () => Get.to(() => const EqualizerScreen()),
          ),
          // ── Add to playlist ────────────────────────────────────────────
          Obx(() => ctrl.currentSong != null
              ? IconButton(
                  icon: const Icon(Icons.playlist_add_rounded,
                      color: Colors.white54),
                  tooltip: 'Add to playlist',
                  onPressed: () =>
                      _showAddToPlaylist(context, ctrl.currentSong!.path),
                )
              : const SizedBox.shrink()),
        ],
        // ── Tab bar as title ───────────────────────────────────────────────
        title: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: 'Now Playing'),
            Tab(text: 'Queue'),
          ],
          labelColor: AppTheme.primary,
          unselectedLabelColor: Colors.white38,
          indicatorColor: AppTheme.primary,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _PlayerTab(
              ctrl: ctrl,
              onAddToPlaylist: (path) => _showAddToPlaylist(context, path)),
          _QueueTab(ctrl: ctrl),
        ],
      ),
    );
  }

  void _showAddToPlaylist(BuildContext context, String songPath) {
    final plCtrl = Get.find<PlaylistController>();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Obx(() => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12)),
                      onTap: () {
                        plCtrl.addSongToPlaylist(pl.id, songPath);
                        Get.back();
                        Get.snackbar('Added', 'Song added to ${pl.name}',
                            backgroundColor: AppTheme.surface,
                            colorText: Colors.white,
                            duration: const Duration(seconds: 2),
                            snackPosition: SnackPosition.BOTTOM);
                      },
                    )),
              const SizedBox(height: 16),
            ],
          )),
    );
  }
}

// ─── Player Tab ───────────────────────────────────────────────
class _PlayerTab extends StatelessWidget {
  final PlayerController ctrl;
  final Function(String) onAddToPlaylist;
  const _PlayerTab({required this.ctrl, required this.onAddToPlaylist});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.currentSong == null) {
        return const Center(
            child: Text('Nothing playing',
                style: TextStyle(color: Colors.white38)));
      }

      // ── FIX: Use LayoutBuilder for a fully responsive player UI ─────────
      // Previously the player used hardcoded sizes (220x220 album art, etc.)
      // which caused overflow on small screens and wasted space on large ones.
      // LayoutBuilder adapts every element to the available height.
      return LayoutBuilder(
        builder: (context, constraints) {
          final availH = constraints.maxHeight;
          // Determine album art size: take up ~35% of available height,
          // capped at 260 and minimum 140.
          final artSize = (availH * 0.35).clamp(140.0, 260.0);
          // Vertical padding scales with available space
          final vPad = (availH * 0.03).clamp(8.0, 24.0);

          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: vPad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AlbumArt(size: artSize),
                  SizedBox(height: vPad),
                  _SongInfo(ctrl: ctrl),
                  SizedBox(height: vPad * 0.8),
                  _SeekBar(ctrl: ctrl),
                  SizedBox(height: vPad * 0.6),
                  _Controls(ctrl: ctrl),
                  SizedBox(height: vPad),
                ],
              ),
            ),
          );
        },
      );
    });
  }
}

// ─── Album Art — size is now passed in ────────────────────────────────────
class _AlbumArt extends StatelessWidget {
  final double size;
  const _AlbumArt({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
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
        Obx(() => Text(
              '${ctrl.currentSong?.ext.toUpperCase() ?? ''} · ${ctrl.queueSource.value}',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            )),
      ]),
    );
  }
}

// ─── SeekBar — StatefulWidget so only it rebuilds on position tick ──────────
class _SeekBar extends StatefulWidget {
  final PlayerController ctrl;
  const _SeekBar({required this.ctrl});
  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final dur = widget.ctrl.duration.value.inSeconds.toDouble();
      final pos = _dragValue ?? widget.ctrl.position.value.inSeconds.toDouble();
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
              onChangeStart: (v) => setState(() => _dragValue = v),
              onChanged: dur > 0 ? (v) => setState(() => _dragValue = v) : null,
              onChangeEnd: (v) {
                widget.ctrl.seek(v);
                setState(() => _dragValue = null);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _fmt(_dragValue != null
                        ? Duration(seconds: _dragValue!.toInt())
                        : widget.ctrl.position.value),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  Text(_fmt(widget.ctrl.duration.value),
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 12)),
                ]),
          ),
        ]),
      );
    });
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
              IconButton(
                icon: Icon(Icons.shuffle_rounded,
                    color: ctrl.shuffleEnabled.value
                        ? AppTheme.primary
                        : Colors.white38,
                    size: 22),
                onPressed: ctrl.toggleShuffle,
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded,
                    color: Colors.white, size: 32),
                onPressed: ctrl.playPrev,
              ),
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
              IconButton(
                icon: const Icon(Icons.skip_next_rounded,
                    color: Colors.white, size: 32),
                onPressed: ctrl.playNext,
              ),
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

// ─── Queue Tab — reorderable ──────────────────────────────────────────────
class _QueueTab extends StatelessWidget {
  final PlayerController ctrl;
  const _QueueTab({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.queue.isEmpty) {
        return const Center(
            child: Text('Queue is empty',
                style: TextStyle(color: Colors.white38)));
      }

      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${ctrl.queue.length} songs · ${ctrl.queueSource.value}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const Text('Hold to reorder',
                  style: TextStyle(color: Colors.white24, fontSize: 12)),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: ctrl.queue.length,
            onReorder: ctrl.reorderQueue,
            proxyDecorator: (child, index, animation) => Material(
              color: Colors.transparent,
              child: child,
            ),
            itemBuilder: (_, i) {
              final song = ctrl.queue[i];
              final isCurrent = i == ctrl.queueIndex.value;
              return ListTile(
                key: ValueKey(song.path + i.toString()),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? AppTheme.primary.withOpacity(0.2)
                        : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: isCurrent && ctrl.isPlaying.value
                      ? const Icon(Icons.equalizer_rounded,
                          color: AppTheme.primary, size: 16)
                      : Center(
                          child: Text('${i + 1}',
                              style: TextStyle(
                                  color: isCurrent
                                      ? AppTheme.primary
                                      : Colors.white30,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold))),
                ),
                title: Text(song.name,
                    style: TextStyle(
                        color: isCurrent ? AppTheme.primary : Colors.white,
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(song.ext.toUpperCase(),
                    style:
                        const TextStyle(color: Colors.white24, fontSize: 11)),
                trailing: isCurrent
                    ? const Icon(Icons.volume_up_rounded,
                        color: AppTheme.primary, size: 16)
                    : IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white24, size: 18),
                        onPressed: () => ctrl.removeFromQueue(i),
                        padding: EdgeInsets.zero,
                      ),
                onTap: () => ctrl.playByQueueIndex(i),
              );
            },
          ),
        ),
      ]);
    });
  }
}
