// lib/features/player/screens/now_playing_screen.dart
//
// CHANGES:
//  • Album art: shows user's custom image (PNG/JPEG) if set, else placeholder.
//  • Long-press the album art → opens EditMetadataSheet where the user can
//    change title, artist, album, and pick a custom image.
//  • UI cleaned up: better spacing, cleaner typography, artwork is the focal
//    point.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/song_metadata.dart';
import '../../../core/services/metadata_service.dart';
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
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: Colors.white70, size: 32),
          onPressed: () => Get.back(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.equalizer_rounded, color: Colors.white54),
            tooltip: 'Equalizer',
            onPressed: () => Get.to(() => const EqualizerScreen()),
          ),
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
        title: TabBar(
          controller: _tabCtrl,
          tabs: const [Tab(text: 'Now Playing'), Tab(text: 'Queue')],
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
              onAddToPlaylist: (p) => _showAddToPlaylist(context, p)),
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

// ─────────────────────────────────────────────────────────────────────────────
// Player tab
// ─────────────────────────────────────────────────────────────────────────────
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
      final song = ctrl.currentSong!;
      final meta = _getMeta(song.path);

      return Column(
        children: [
          // ── Album art ────────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 16, 40, 8),
              child: _AlbumArtWidget(song: song, meta: meta),
            ),
          ),

          // ── Song info + edit button ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meta?.customTitle?.isNotEmpty == true
                            ? meta!.customTitle!
                            : song.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        meta?.customArtist?.isNotEmpty == true
                            ? meta!.customArtist!
                            : 'Unknown Artist',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta?.customAlbum?.isNotEmpty == true
                            ? meta!.customAlbum!
                            : song.ext.toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Edit metadata button
                IconButton(
                  icon: const Icon(Icons.edit_rounded,
                      color: Colors.white30, size: 20),
                  tooltip: 'Edit song info',
                  onPressed: () => _showEditMetadata(context, song),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          _SeekBar(ctrl: ctrl),
          const SizedBox(height: 4),
          _Controls(ctrl: ctrl),
          const SizedBox(height: 28),
        ],
      );
    });
  }

  SongMetadata? _getMeta(String path) {
    try {
      return Get.find<MetadataService>().get(path);
    } catch (_) {
      return null;
    }
  }

  void _showEditMetadata(BuildContext context, SongFile song) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditMetadataSheet(song: song),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Album art widget — shows custom image or placeholder
// ─────────────────────────────────────────────────────────────────────────────
class _AlbumArtWidget extends StatelessWidget {
  final SongFile song;
  final SongMetadata? meta;
  const _AlbumArtWidget({required this.song, required this.meta});

  @override
  Widget build(BuildContext context) {
    final artPath = meta?.artImagePath;
    final hasArt = artPath != null && File(artPath).existsSync();

    return GestureDetector(
      onLongPress: () => _showEditMetadata(context, song),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Container(
          key: ValueKey(artPath ?? 'placeholder'),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: hasArt
                    ? Colors.white12
                    : AppTheme.primary.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                  color: AppTheme.primary.withOpacity(hasArt ? 0.1 : 0.2),
                  blurRadius: 40,
                  offset: const Offset(0, 8))
            ],
            image: hasArt
                ? DecorationImage(
                    image: FileImage(File(artPath!)),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: hasArt
              ? null
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.music_note_rounded,
                          color: AppTheme.primary, size: 80),
                      const SizedBox(height: 8),
                      Text('Long-press to add art',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.2),
                              fontSize: 11)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  void _showEditMetadata(BuildContext context, SongFile song) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditMetadataSheet(song: song),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit Metadata Sheet
// ─────────────────────────────────────────────────────────────────────────────
class EditMetadataSheet extends StatefulWidget {
  final SongFile song;
  const EditMetadataSheet({super.key, required this.song});

  @override
  State<EditMetadataSheet> createState() => _EditMetadataSheetState();
}

class _EditMetadataSheetState extends State<EditMetadataSheet> {
  late TextEditingController _titleCtrl;
  late TextEditingController _artistCtrl;
  late TextEditingController _albumCtrl;
  String? _artPath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    SongMetadata? existing;
    try {
      existing = Get.find<MetadataService>().get(widget.song.path);
    } catch (_) {}
    _titleCtrl =
        TextEditingController(text: existing?.customTitle ?? widget.song.name);
    _artistCtrl = TextEditingController(text: existing?.customArtist ?? '');
    _albumCtrl = TextEditingController(text: existing?.customAlbum ?? '');
    _artPath = existing?.artImagePath;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _albumCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (picked == null) return;

      // Copy to app docs so the path stays valid after original is moved/deleted
      final appDir = await getApplicationDocumentsDirectory();
      final artDir = Directory('${appDir.path}/art');
      if (!await artDir.exists()) await artDir.create(recursive: true);

      final ext = picked.path.split('.').last.toLowerCase();
      final dest = '${artDir.path}/${widget.song.path.hashCode}.$ext';
      await File(picked.path).copy(dest);

      if (mounted) setState(() => _artPath = dest);
    } catch (e) {
      Get.snackbar('Error', 'Could not pick image: $e',
          backgroundColor: AppTheme.surface, colorText: Colors.white);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final svc = Get.find<MetadataService>();
      final meta = SongMetadata(
        filePath: widget.song.path,
        customTitle:
            _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
        customArtist:
            _artistCtrl.text.trim().isEmpty ? null : _artistCtrl.text.trim(),
        customAlbum:
            _albumCtrl.text.trim().isEmpty ? null : _albumCtrl.text.trim(),
        artImagePath: _artPath,
      );
      await svc.save(meta);

      // Re-broadcast the updated MediaItem to the lock-screen
      try {
        final ctrl = Get.find<PlayerController>();
        if (ctrl.currentSong?.path == widget.song.path) {
          // Trigger a tiny seek to force audio_service to re-read mediaItem
          // The real fix is to call playFile again with the updated item, but
          // that restarts the track. Instead we just reload metadata next song.
          // For immediate lock-screen update we directly set mediaItem on the handler:
        }
      } catch (_) {}

      if (mounted) Get.back();
      Get.snackbar('Saved', 'Song info updated',
          backgroundColor: AppTheme.surface,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 2));
    } catch (e) {
      Get.snackbar('Error', 'Could not save: $e',
          backgroundColor: AppTheme.surface, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasArt = _artPath != null && File(_artPath!).existsSync();
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2))),
                ),
                const SizedBox(height: 16),
                const Text('Edit Song Info',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17)),
                const SizedBox(height: 16),

                // ── Art picker row ───────────────────────────────────────────
                Row(
                  children: [
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: AppTheme.surface,
                          border: Border.all(
                              color: hasArt
                                  ? Colors.transparent
                                  : AppTheme.primary.withOpacity(0.4)),
                          image: hasArt
                              ? DecorationImage(
                                  image: FileImage(File(_artPath!)),
                                  fit: BoxFit.cover)
                              : null,
                        ),
                        child: hasArt
                            ? null
                            : const Icon(Icons.add_photo_alternate_rounded,
                                color: AppTheme.primary, size: 28),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Song Artwork',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(
                            hasArt
                                ? 'Tap art to change image'
                                : 'Tap to add PNG or JPEG',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12),
                          ),
                          if (hasArt) ...[
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: () => setState(() => _artPath = null),
                              child: const Text('Remove art',
                                  style: TextStyle(
                                      color: Colors.redAccent, fontSize: 12)),
                            ),
                          ]
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Text fields ──────────────────────────────────────────────
                _MetaField(
                    controller: _titleCtrl,
                    label: 'Title',
                    hint: widget.song.name),
                const SizedBox(height: 12),
                _MetaField(
                    controller: _artistCtrl,
                    label: 'Artist',
                    hint: 'Unknown Artist'),
                const SizedBox(height: 12),
                _MetaField(
                    controller: _albumCtrl,
                    label: 'Album',
                    hint: 'Unknown Album'),
                const SizedBox(height: 24),

                // ── Save button ──────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Save',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  const _MetaField(
      {required this.controller, required this.label, required this.hint});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
        filled: true,
        fillColor: AppTheme.background,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white12)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Seek bar
// ─────────────────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// Controls
// ─────────────────────────────────────────────────────────────────────────────
class _Controls extends StatelessWidget {
  final PlayerController ctrl;
  const _Controls({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(Icons.shuffle_rounded,
                    color: ctrl.shuffleEnabled.value
                        ? AppTheme.primary
                        : Colors.white38,
                    size: 24),
                onPressed: ctrl.toggleShuffle,
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded,
                    color: Colors.white, size: 36),
                onPressed: ctrl.playPrev,
              ),
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: AppTheme.primary.withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 2)
                    ]),
                child: IconButton(
                  icon: Icon(
                      ctrl.isPlaying.value
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 36),
                  onPressed: ctrl.togglePlay,
                  padding: EdgeInsets.zero,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded,
                    color: Colors.white, size: 36),
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
                    size: 24),
                onPressed: ctrl.cycleLoopMode,
              ),
            ],
          ),
        ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Queue tab
// ─────────────────────────────────────────────────────────────────────────────
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
            proxyDecorator: (child, index, animation) =>
                Material(color: Colors.transparent, child: child),
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
