import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/theme/app_theme.dart';
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
                boxShadow: [
                  BoxShadow(
                      color: Colors.black45,
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: suggestions
                    .map((s) => InkWell(
                          onTap: () {
                            _searchCtrl.text = s;
                            ctrl.filterSongs(s);
                            _removeSuggestions();
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
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 10),
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
            if (suggestions.isNotEmpty) {
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
        itemExtent: 68,
        itemBuilder: (_, i) {
          final song = ctrl.filteredSongs[i];
          return Obx(() {
            final isCurrent = ctrl.isCurrentSong(song.path);
            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? AppTheme.primary.withOpacity(0.2)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: isCurrent && ctrl.isPlaying.value
                    ? const Icon(Icons.equalizer_rounded,
                        color: AppTheme.primary, size: 18)
                    : Icon(_iconForExt(song.ext),
                        color: isCurrent ? AppTheme.primary : Colors.white30,
                        size: 18),
              ),
              title: Text(song.name,
                  style: TextStyle(
                    color: isCurrent ? AppTheme.primary : Colors.white,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              subtitle: Text(song.ext.toUpperCase(),
                  style: const TextStyle(color: Colors.white30, fontSize: 11)),
              onTap: () async {
                _removeSuggestions();
                await ctrl.playSong(i);
                Get.to(() => const NowPlayingScreen(),
                    transition: Transition.downToUp);
              },
              // Long-press → context menu
              onLongPress: () => _showSongOptions(context, ctrl, song),
            );
          });
        },
      );
    });
  }

  void _showSongOptions(
      BuildContext context, PlayerController ctrl, SongFile song) {
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
          ListTile(
            leading:
                const Icon(Icons.playlist_add_rounded, color: Colors.white54),
            title: const Text('Add to Playlist',
                style: TextStyle(color: Colors.white)),
            onTap: () {
              Get.back();
              // Navigate to now playing with add-to-playlist action
              Get.to(() => const NowPlayingScreen(),
                  transition: Transition.downToUp);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  IconData _iconForExt(String ext) {
    return switch (ext.toLowerCase()) {
      'mp3' => Icons.music_note_rounded,
      'flac' => Icons.high_quality_rounded,
      'm4a' || 'aac' => Icons.audiotrack_rounded,
      'wav' => Icons.graphic_eq_rounded,
      _ => Icons.audio_file_rounded,
    };
  }
}

class _MiniPlayer extends StatelessWidget {
  final PlayerController ctrl;
  const _MiniPlayer({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.currentSong == null) return const SizedBox.shrink();
      final song = ctrl.currentSong!;
      final dur = ctrl.duration.value.inSeconds.toDouble();
      final pos = ctrl.position.value.inSeconds.toDouble();

      return GestureDetector(
        onTap: () => Get.to(() => const NowPlayingScreen(),
            transition: Transition.downToUp),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.music_note_rounded,
                    color: AppTheme.primary, size: 18),
              ),
              const SizedBox(width: 10),
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
                      Text(ctrl.queueSource.value,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
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
                onChanged: dur > 0 ? ctrl.seek : null,
              ),
            ),
          ]),
        ),
      );
    });
  }
}
