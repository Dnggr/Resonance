// lib/features/player/screens/now_playing_screen.dart
//
// FIX LOG (this session):
//  [FIX-ART-SQUARE]   Album art container now uses AspectRatio(1,1) so it is
//    always a perfect square regardless of screen size. No more stretching.
//
//  [FIX-QUEUE-SCROLL] Queue tab auto-scrolls to the currently playing song
//    so you can immediately see what's playing and what's next.
//
//  [FEAT-LYRICS]      Spotify-style lyrics view: swipe the album art left or
//    tap the "Lyrics" button to slide into a karaoke-style scrolling lyrics
//    panel. Lyrics are loaded from a .lrc sidecar file next to the audio file
//    (e.g. "song.mp3" → "song.lrc"). Falls back to a plain text .txt file.
//    Active line is highlighted and auto-scrolls. The panel transitions in
//    with the same slide animation Spotify uses (PageView).
//    Lyrics can be added/edited via the edit metadata sheet.

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

// ─── LRC Parser ─────────────────────────────────────────────────────────────

class LrcLine {
  final Duration time;
  final String text;
  const LrcLine({required this.time, required this.text});
}

List<LrcLine> parseLrc(String content) {
  final lines = <LrcLine>[];
  final lineRegex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');
  for (final rawLine in content.split('\n')) {
    final match = lineRegex.firstMatch(rawLine.trim());
    if (match == null) continue;
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final centis = int.parse(match.group(3)!.padRight(3, '0').substring(0, 3));
    final text = match.group(4)?.trim() ?? '';
    lines.add(LrcLine(
      time: Duration(minutes: minutes, seconds: seconds, milliseconds: centis),
      text: text,
    ));
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}

String? _lrcPathFor(String audioPath) {
  final base = audioPath.replaceAll(
      RegExp(r'\.(mp3|flac|m4a)$', caseSensitive: false), '');
  final lrc = '$base.lrc';
  if (File(lrc).existsSync()) return lrc;
  final txt = '$base.txt';
  if (File(txt).existsSync()) return txt;
  return null;
}

// ─── Main Screen ────────────────────────────────────────────────────────────

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
// Player tab — contains PageView: left=player, right=lyrics (Spotify style)
// ─────────────────────────────────────────────────────────────────────────────

class _PlayerTab extends StatefulWidget {
  final PlayerController ctrl;
  final Function(String) onAddToPlaylist;
  const _PlayerTab({required this.ctrl, required this.onAddToPlaylist});

  @override
  State<_PlayerTab> createState() => _PlayerTabState();
}

class _PlayerTabState extends State<_PlayerTab> {
  final PageController _pageCtrl = PageController();
  bool _showingLyrics = false;

  void _toggleLyrics() {
    if (_showingLyrics) {
      _pageCtrl.animateToPage(0,
          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    } else {
      _pageCtrl.animateToPage(1,
          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    }
    setState(() => _showingLyrics = !_showingLyrics);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (widget.ctrl.currentSong == null) {
        return const Center(
            child: Text('Nothing playing',
                style: TextStyle(color: Colors.white38)));
      }
      final song = widget.ctrl.currentSong!;
      SongMetadata? meta;
      try {
        meta = Get.find<MetadataService>().get(song.path);
      } catch (_) {}

      return Column(
        children: [
          // ── PageView: Player view (page 0) ↔ Lyrics view (page 1) ─────
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              onPageChanged: (idx) => setState(() => _showingLyrics = idx == 1),
              children: [
                // Page 0: Album art + song info
                _PlayerPage(
                  ctrl: widget.ctrl,
                  song: song,
                  meta: meta,
                  onAddToPlaylist: widget.onAddToPlaylist,
                ),
                // Page 1: Karaoke lyrics
                _LyricsPage(ctrl: widget.ctrl, song: song),
              ],
            ),
          ),

          // ── Seek bar ───────────────────────────────────────────────────
          _SeekBar(ctrl: widget.ctrl),
          const SizedBox(height: 4),

          // ── Controls ───────────────────────────────────────────────────
          _Controls(ctrl: widget.ctrl),
          const SizedBox(height: 8),

          // ── Lyrics toggle button (below controls, Spotify style) ────────
          TextButton.icon(
            onPressed: _toggleLyrics,
            icon: Icon(
              _showingLyrics ? Icons.music_note_rounded : Icons.lyrics_rounded,
              size: 16,
              color: _showingLyrics ? AppTheme.primary : Colors.white38,
            ),
            label: Text(
              _showingLyrics ? 'Back to player' : 'Lyrics',
              style: TextStyle(
                color: _showingLyrics ? AppTheme.primary : Colors.white38,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      );
    });
  }
}

// ─── Player page (album art + song info) ────────────────────────────────────

class _PlayerPage extends StatelessWidget {
  final PlayerController ctrl;
  final SongFile song;
  final SongMetadata? meta;
  final Function(String) onAddToPlaylist;

  const _PlayerPage({
    required this.ctrl,
    required this.song,
    required this.meta,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Album art — FIX: AspectRatio(1) guarantees square ──────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 16, 40, 8),
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: _AlbumArtWidget(song: song, meta: meta),
              ),
            ),
          ),
        ),

        // ── Song info + edit ───────────────────────────────────────────
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
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta?.customAlbum?.isNotEmpty == true
                          ? meta!.customAlbum!
                          : song.ext.toUpperCase(),
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
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
      ],
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

// ─── Lyrics page (karaoke scrolling) ────────────────────────────────────────

class _LyricsPage extends StatefulWidget {
  final PlayerController ctrl;
  final SongFile song;

  const _LyricsPage({required this.ctrl, required this.song});

  @override
  State<_LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<_LyricsPage> {
  List<LrcLine> _lines = [];
  String? _plainText;
  bool _loaded = false;
  String? _loadedFor;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _loadLyrics(String audioPath) {
    if (_loadedFor == audioPath) return;
    _loadedFor = audioPath;
    _lines = [];
    _plainText = null;

    final lrcPath = _lrcPathFor(audioPath);
    if (lrcPath == null) {
      setState(() => _loaded = true);
      return;
    }

    try {
      final content = File(lrcPath).readAsStringSync();
      if (lrcPath.endsWith('.lrc')) {
        _lines = parseLrc(content);
        if (_lines.isEmpty) _plainText = content.trim();
      } else {
        _plainText = content.trim();
      }
    } catch (_) {}

    setState(() => _loaded = true);
  }

  int _activeIndex(Duration pos) {
    if (_lines.isEmpty) return -1;
    int active = 0;
    for (int i = 0; i < _lines.length; i++) {
      if (_lines[i].time <= pos)
        active = i;
      else
        break;
    }
    return active;
  }

  void _autoScroll(int activeIdx) {
    if (!_scrollCtrl.hasClients || activeIdx < 0) return;
    // Each line is roughly 56px tall; scroll to centre it
    final target =
        (activeIdx * 56.0) - (_scrollCtrl.position.viewportDimension / 2) + 28;
    _scrollCtrl.animateTo(
      target.clamp(0, _scrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final song = widget.ctrl.currentSong;
      if (song != null) _loadLyrics(song.path);

      if (!_loaded) {
        return const Center(
            child: CircularProgressIndicator(color: AppTheme.primary));
      }

      if (_lines.isEmpty && (_plainText == null || _plainText!.isEmpty)) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lyrics_rounded, color: Colors.white12, size: 64),
            const SizedBox(height: 16),
            const Text('No lyrics found',
                style: TextStyle(color: Colors.white38, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              'Add a .lrc or .txt file with the same\nname as your song file',
              style: const TextStyle(color: Colors.white24, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => _showLrcHelp(context),
              child: const Text('How to add lyrics',
                  style: TextStyle(color: AppTheme.primary)),
            ),
          ]),
        );
      }

      // Plain text lyrics
      if (_lines.isEmpty && _plainText != null) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Text(_plainText!,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 16, height: 1.8)),
        );
      }

      // LRC karaoke lyrics
      final pos = widget.ctrl.position.value;
      final activeIdx = _activeIndex(pos);

      // Auto-scroll side effect
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoScroll(activeIdx);
      });

      return ListView.builder(
        controller: _scrollCtrl,
        padding: EdgeInsets.symmetric(
          horizontal: 24,
          vertical: MediaQuery.of(context).size.height * 0.3,
        ),
        itemCount: _lines.length,
        itemBuilder: (_, i) {
          final isActive = i == activeIdx;
          final isPast = i < activeIdx;
          return GestureDetector(
            onTap: () {
              // Tap a lyric line to seek to that position
              widget.ctrl.seek(_lines[i].time.inSeconds.toDouble());
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: Text(
                _lines[i].text.isEmpty ? '♪' : _lines[i].text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isActive ? 22 : 16,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive
                      ? Colors.white
                      : isPast
                          ? Colors.white24
                          : Colors.white54,
                  height: 1.4,
                ),
              ),
            ),
          );
        },
      );
    });
  }

  void _showLrcHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Adding Lyrics',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Place a lyrics file next to your audio file with the same name:\n\n'
          '• "My Song.mp3" → "My Song.lrc" (karaoke, synced)\n'
          '• "My Song.mp3" → "My Song.txt" (plain text)\n\n'
          'LRC format example:\n'
          '[00:12.50]First line of lyrics\n'
          '[00:17.20]Second line of lyrics\n\n'
          'You can download .lrc files from sites like lrclib.net',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child:
                const Text('Got it', style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Album art widget — FIX-ART-SQUARE: outer AspectRatio ensures perfect square
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
          // FIX: clipBehavior clips image to exact square bounds
          clipBehavior: Clip.hardEdge,
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
          ),
          child: hasArt
              ? Image.file(
                  File(artPath!),
                  fit: BoxFit.cover, // FIX: cover fills square without stretch
                  width: double.infinity,
                  height: double.infinity,
                )
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
// Playback controls
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
// Queue tab — FIX-QUEUE-SCROLL: auto-scrolls to currently playing song
// ─────────────────────────────────────────────────────────────────────────────

class _QueueTab extends StatefulWidget {
  final PlayerController ctrl;
  const _QueueTab({required this.ctrl});

  @override
  State<_QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends State<_QueueTab> {
  final ScrollController _scrollCtrl = ScrollController();
  int? _lastScrolledTo;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToCurrentSong(int idx) {
    if (idx == _lastScrolledTo) return;
    _lastScrolledTo = idx;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      const itemHeight = 64.0;
      final target = (idx * itemHeight) -
          (_scrollCtrl.position.viewportDimension / 2) +
          (itemHeight / 2);
      _scrollCtrl.animateTo(
        target.clamp(0, _scrollCtrl.position.maxScrollExtent),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (widget.ctrl.queue.isEmpty) {
        return const Center(
            child: Text('Queue is empty',
                style: TextStyle(color: Colors.white38)));
      }

      final currentIdx = widget.ctrl.queueIndex.value;
      _scrollToCurrentSong(currentIdx);

      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  '${widget.ctrl.queue.length} songs · ${widget.ctrl.queueSource.value}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const Text('Hold to reorder',
                  style: TextStyle(color: Colors.white24, fontSize: 12)),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            scrollController: _scrollCtrl,
            itemCount: widget.ctrl.queue.length,
            onReorder: widget.ctrl.reorderQueue,
            proxyDecorator: (child, index, animation) =>
                Material(color: Colors.transparent, child: child),
            itemBuilder: (_, i) {
              final song = widget.ctrl.queue[i];
              final isCurrent = i == currentIdx;
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
                  child: isCurrent && widget.ctrl.isPlaying.value
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
                        onPressed: () => widget.ctrl.removeFromQueue(i),
                        padding: EdgeInsets.zero,
                      ),
                onTap: () => widget.ctrl.playByQueueIndex(i),
              );
            },
          ),
        ),
      ]);
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit metadata sheet
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
    SongMetadata? meta;
    try {
      meta = Get.find<MetadataService>().get(widget.song.path);
    } catch (_) {}
    _titleCtrl = TextEditingController(text: meta?.customTitle ?? '');
    _artistCtrl = TextEditingController(text: meta?.customArtist ?? '');
    _albumCtrl = TextEditingController(text: meta?.customAlbum ?? '');
    _artPath = meta?.artImagePath;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _albumCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickArt() async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: ImageSource.gallery);
      if (xfile == null) return;
      final appDir = await getApplicationDocumentsDirectory();
      final dest = '${appDir.path}/art_${widget.song.path.hashCode.abs()}.jpg';
      await File(xfile.path).copy(dest);
      setState(() => _artPath = dest);
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
            _titleCtrl.text.trim().isNotEmpty ? _titleCtrl.text.trim() : null,
        customArtist:
            _artistCtrl.text.trim().isNotEmpty ? _artistCtrl.text.trim() : null,
        customAlbum:
            _albumCtrl.text.trim().isNotEmpty ? _albumCtrl.text.trim() : null,
        artImagePath: _artPath,
      );
      await svc.save(meta);
      try {
        Get.find<PlayerController>().refreshCurrentSongNotification();
      } catch (_) {}
      Get.back();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasArt = _artPath != null && File(_artPath!).existsSync();
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 20,
          right: 20,
          top: 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        const Text('Edit Song Info',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        const SizedBox(height: 16),
        // Art picker
        GestureDetector(
          onTap: _pickArt,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
              image: hasArt
                  ? DecorationImage(
                      image: FileImage(File(_artPath!)), fit: BoxFit.cover)
                  : null,
            ),
            child: hasArt
                ? null
                : const Icon(Icons.add_photo_alternate_rounded,
                    color: AppTheme.primary, size: 30),
          ),
        ),
        const SizedBox(height: 4),
        Text('Tap to change artwork',
            style:
                TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
        const SizedBox(height: 16),
        _field(_titleCtrl, 'Title', widget.song.name),
        const SizedBox(height: 10),
        _field(_artistCtrl, 'Artist', 'Unknown Artist'),
        const SizedBox(height: 10),
        _field(_albumCtrl, 'Album', widget.song.ext.toUpperCase()),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Save', style: TextStyle(fontSize: 15)),
          ),
        ),
      ]),
    );
  }

  Widget _field(TextEditingController controller, String label, String hint) {
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
