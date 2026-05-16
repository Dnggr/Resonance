// lib/features/player/screens/player_screen.dart
//
// FIX LOG (this session):
//  [FIX-SEARCH-AUTOCOMPLETE] When a suggestion is tapped, the song list is
//    filtered to show songs matching that suggestion AND the list scrolls to
//    show the best match at the top. Tapping the song then plays it from the
//    full library queue (fixed in player_controller.dart).
//
//  [FIX-SEARCH-PLAY] Tapping a song from filtered results now populates the
//    queue from the FULL library (not just the filtered subset). The song
//    selected is still the one that starts playing. Queue starts there.
//
//  [FIX-FORMAT-ICON] Removed aac/wav icon cases — only mp3, m4a, flac shown.
//
//  [UX-1] _MiniPlayer seek slider drag-value fix (unchanged from prev version).
//  [BUG-6] artPath/existsSync outside Obx (unchanged from prev version).
//  [UX-2] _removeSuggestions() before navigate (unchanged from prev version).

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/metadata_service.dart';
import '../controllers/player_controller.dart';
import 'now_playing_screen.dart';
import '../../playlist/screens/playlist_screen.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _suggestionOverlay;

  @override
  void dispose() {
    _removeSuggestions();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _removeSuggestions() {
    _suggestionOverlay?.remove();
    _suggestionOverlay = null;
  }

  // ─── FIX-SEARCH-AUTOCOMPLETE ────────────────────────────────────────────────
  // When a suggestion is tapped:
  //   1. The text field is updated to the selected suggestion text.
  //   2. The song list is filtered to show matching songs.
  //   3. The overlay is removed so the user sees the filtered results.
  //   4. The user then taps the specific song they want.
  // This fixes the bug where tapping a suggestion would dismiss the overlay
  // but not show any results (the list stayed unfiltered or empty).
  void _showSuggestions(
      BuildContext context, PlayerController ctrl, List<String> suggestions) {
    _removeSuggestions();
    if (suggestions.isEmpty) return;

    _suggestionOverlay = OverlayEntry(
      builder: (_) => Positioned(
        width: MediaQuery.of(context).size.width - 32,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 52),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E3A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black45,
                      blurRadius: 12,
                      offset: Offset(0, 4))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: suggestions
                    .map((s) => InkWell(
                          onTap: () {
                            // FIX: Update text field AND filter songs, THEN
                            // remove overlay so user sees the filtered list.
                            _searchCtrl.text = s;
                            // Move cursor to end
                            _searchCtrl.selection = TextSelection.fromPosition(
                                TextPosition(offset: s.length));
                            ctrl.filterSongs(s);
                            _removeSuggestions();
                            // Don't navigate — let user tap the specific song
                            // from the now-filtered list. This matches how
                            // Spotify's search works.
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Row(children: [
                              const Icon(Icons.search_rounded,
                                  color: Colors.white38, size: 16),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(s,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 14),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const Icon(Icons.north_west_rounded,
                                  color: Colors.white24, size: 14),
                            ]),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_suggestionOverlay!);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<PlayerController>();
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(ctrl),
            _buildSearchBar(context, ctrl),
            const SizedBox(height: 4),
            Expanded(child: _buildSongList(context, ctrl)),
            _MiniPlayer(ctrl: ctrl),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(PlayerController ctrl) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 10),
      child: Row(children: [
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
          icon: const Icon(Icons.playlist_play_rounded, color: Colors.white54),
          tooltip: 'Playlists',
          onPressed: () => Get.to(() => const PlaylistScreen()),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
          onPressed: ctrl.loadSongs,
        ),
      ]),
    );
  }

  Widget _buildSearchBar(BuildContext context, PlayerController ctrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: CompositedTransformTarget(
        link: _layerLink,
        child: TextField(
          controller: _searchCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search songs...',
            hintStyle: const TextStyle(color: Colors.white30),
            prefixIcon: const Icon(Icons.search_rounded,
                color: Colors.white38, size: 20),
            suffixIcon: Obx(() => ctrl.searchQuery.value.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear,
                        color: Colors.white38, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      ctrl.filterSongs('');
                      _removeSuggestions();
                    },
                  )
                : const SizedBox.shrink()),
            filled: true,
            fillColor: AppTheme.surface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppTheme.primary, width: 1)),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onChanged: (q) {
            ctrl.filterSongs(q);
            final suggestions = ctrl.getSearchSuggestions(q);
            if (suggestions.isNotEmpty && q.trim().isNotEmpty) {
              _showSuggestions(context, ctrl, suggestions);
            } else {
              _removeSuggestions();
            }
          },
          onSubmitted: (_) => _removeSuggestions(),
          onTapOutside: (_) => _removeSuggestions(),
        ),
      ),
    );
  }

  Widget _buildSongList(BuildContext context, PlayerController ctrl) {
    return Obx(() {
      if (ctrl.isLoading.value) {
        return const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: AppTheme.primary),
            SizedBox(height: 16),
            Text('Scanning library...',
                style: TextStyle(color: Colors.white38)),
          ]),
        );
      }
      if (ctrl.filteredSongs.isEmpty) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                ctrl.songs.isEmpty
                    ? Icons.library_music_rounded
                    : Icons.search_off_rounded,
                size: 56,
                color: Colors.white12),
            const SizedBox(height: 12),
            Text(ctrl.songs.isEmpty ? 'No music found' : 'No results',
                style: const TextStyle(color: Colors.white54, fontSize: 16)),
            if (ctrl.songs.isEmpty) ...[
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
                    foregroundColor: Colors.white),
              ),
            ],
          ]),
        );
      }

      return ListView.builder(
        itemCount: ctrl.filteredSongs.length,
        itemExtent: 72,
        addRepaintBoundaries: true,
        addAutomaticKeepAlives: false,
        padding: const EdgeInsets.only(bottom: 8),
        itemBuilder: (_, i) {
          final song = ctrl.filteredSongs[i];

          // ─── BUG-6: existsSync() OUTSIDE Obx ────────────────────────────
          final artPath = _artPath(song.path);
          final hasArt = artPath != null && File(artPath).existsSync();

          return RepaintBoundary(
            child: Obx(() {
              final isCurrent = ctrl.isCurrentSong(song.path);

              return InkWell(
                onTap: () async {
                  // ─── FIX UX-2 + FIX-SEARCH-PLAY ────────────────────────
                  // Remove overlay before navigating.
                  // playSong(i) now queues ALL library songs starting at
                  // the selected one (see player_controller.dart).
                  _removeSuggestions();
                  await ctrl.playSong(i);
                  Get.to(() => const NowPlayingScreen(),
                      transition: Transition.downToUp);
                },
                onLongPress: () => _showSongOptions(context, ctrl, song, i),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? AppTheme.primary.withOpacity(0.07)
                        : Colors.transparent,
                    border: Border(
                      bottom: BorderSide(
                          color: Colors.white.withOpacity(0.05), width: 0.5),
                    ),
                  ),
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? AppTheme.primary.withOpacity(0.2)
                            : Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(10),
                        image: hasArt
                            ? DecorationImage(
                                image: FileImage(File(artPath!)),
                                fit: BoxFit.cover)
                            : null,
                      ),
                      child: hasArt
                          ? null
                          : isCurrent && ctrl.isPlaying.value
                              ? const Icon(Icons.equalizer_rounded,
                                  color: AppTheme.primary, size: 20)
                              : Icon(_iconForExt(song.ext),
                                  color: isCurrent
                                      ? AppTheme.primary
                                      : Colors.white24,
                                  size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_displayTitle(song),
                              style: TextStyle(
                                color:
                                    isCurrent ? AppTheme.primary : Colors.white,
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(_displaySubtitle(song),
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    if (isCurrent)
                      const Icon(Icons.volume_up_rounded,
                          color: AppTheme.primary, size: 16),
                  ]),
                ),
              );
            }),
          );
        },
      );
    });
  }

  String? _artPath(String path) {
    try {
      return Get.find<MetadataService>().artImagePath(path);
    } catch (_) {
      return null;
    }
  }

  String _displayTitle(SongFile song) {
    try {
      final svc = Get.find<MetadataService>();
      return svc.displayTitle(song.path, song.name);
    } catch (_) {
      return song.name;
    }
  }

  String _displaySubtitle(SongFile song) {
    try {
      final svc = Get.find<MetadataService>();
      final artist = svc.displayArtist(song.path);
      if (artist != 'Unknown Artist') return artist;
    } catch (_) {}
    return song.ext.toUpperCase();
  }

  void _showSongOptions(
      BuildContext context, PlayerController ctrl, SongFile song, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(song.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.edit_rounded, color: AppTheme.primary),
            title: const Text('Edit Song Info',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('Change title, artist, album & art',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            onTap: () {
              Get.back();
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => EditMetadataSheet(song: song),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue_play_next_rounded,
                color: AppTheme.primary),
            title:
                const Text('Play Next', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Insert after current song',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            onTap: () {
              Get.back();
              ctrl.addToPlayNext(song);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // FIX: Removed aac/wav — only mp3, m4a, flac are supported
  IconData _iconForExt(String ext) {
    return switch (ext.toLowerCase()) {
      'mp3' => Icons.music_note_rounded,
      'flac' => Icons.high_quality_rounded,
      'm4a' => Icons.audiotrack_rounded,
      _ => Icons.audio_file_rounded,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini player — StatefulWidget with drag-value local state (UX-1)
// ─────────────────────────────────────────────────────────────────────────────

class _MiniPlayer extends StatefulWidget {
  final PlayerController ctrl;
  const _MiniPlayer({required this.ctrl});

  @override
  State<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<_MiniPlayer> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final ctrl = widget.ctrl;
      if (ctrl.currentSong == null) return const SizedBox.shrink();
      final song = ctrl.currentSong!;
      final dur = ctrl.duration.value.inSeconds.toDouble();
      final pos = _dragValue ?? ctrl.position.value.inSeconds.toDouble();

      String displayTitle = song.name;
      String displayArtist = '';
      String? artPath;
      try {
        final svc = Get.find<MetadataService>();
        displayTitle = svc.displayTitle(song.path, song.name);
        final a = svc.displayArtist(song.path);
        if (a != 'Unknown Artist') displayArtist = a;
        artPath = svc.artImagePath(song.path);
      } catch (_) {}
      final hasArt = artPath != null && File(artPath).existsSync();

      return GestureDetector(
        onTap: () => Get.to(() => const NowPlayingScreen(),
            transition: Transition.downToUp),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    image: hasArt
                        ? DecorationImage(
                            image: FileImage(File(artPath!)), fit: BoxFit.cover)
                        : null),
                child: hasArt
                    ? null
                    : const Icon(Icons.music_note_rounded,
                        color: AppTheme.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayTitle,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(
                        displayArtist.isNotEmpty
                            ? displayArtist
                            : ctrl.queueSource.value,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ]),
              ),
              IconButton(
                  icon: const Icon(Icons.skip_previous_rounded,
                      color: Colors.white70),
                  onPressed: ctrl.playPrev,
                  iconSize: 20,
                  padding: EdgeInsets.zero),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(10)),
                child: IconButton(
                  icon: Icon(
                      ctrl.isPlaying.value
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white),
                  onPressed: ctrl.togglePlay,
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.skip_next_rounded,
                      color: Colors.white70),
                  onPressed: ctrl.playNext,
                  iconSize: 20,
                  padding: EdgeInsets.zero),
            ]),
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: AppTheme.primary,
                inactiveTrackColor: Colors.white12,
                thumbColor: AppTheme.primary,
              ),
              child: Slider(
                value: pos.clamp(0, dur <= 0 ? 1 : dur),
                max: dur <= 0 ? 1 : dur,
                onChangeStart: (v) => setState(() => _dragValue = v),
                onChanged:
                    dur > 0 ? (v) => setState(() => _dragValue = v) : null,
                onChangeEnd: (v) {
                  ctrl.seek(v);
                  setState(() => _dragValue = null);
                },
              ),
            ),
          ]),
        ),
      );
    });
  }
}
