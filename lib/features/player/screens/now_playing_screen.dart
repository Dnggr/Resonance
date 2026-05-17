// lib/features/player/screens/now_playing_screen.dart
//
// FIXES THIS SESSION:
//  [FIX-QUEUE-OVERFLOW]  Header row text overflow — "RIGHT OVERFLOWED BY X px"
//    was caused by the source label being too long for a plain Text widget inside
//    a Row. Fixed with Flexible + overflow: TextOverflow.ellipsis.
//
//  [FIX-QUEUE-SHUFFLE-ORDER]  In shuffle mode the queue list still showed
//    alphabetical order. The queue list is now reordered to match _shuffleOrder
//    when shuffle is on: the currently playing song is at the top, followed by
//    the upcoming songs in shuffle sequence, then already-played songs greyed out.
//    The controller exposes shuffleOrder and shufflePos as getters for this.
//
//  [FIX-QUEUE-SCROLL-RETRIGGER]  _lastScrolledTo comparison prevented re-scroll
//    when switching tabs. Now scrolls every time the Queue tab becomes visible.
//
//  [FIX-LYRICS-SONG-CHANGE]  When the song advances automatically, _LyricsPage
//    received a new `song` prop but Flutter reused the old State object, leaving
//    the stale ScrollController position and old lyrics data. Fixed by:
//    1. Giving _LyricsPage a ValueKey(song.path) — forces full widget recreation
//       when the song changes, so the scroll position resets to 0.
//    2. The _LyricsPageState._load() guard still prevents redundant network
//       fetches for the same path within one widget lifetime.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/song_metadata.dart';
import '../../../core/services/metadata_service.dart';
import '../controllers/player_controller.dart';
import '../../playlist/controllers/playlist_controller.dart';
import '../../equalizer/screens/equalizer_screen.dart';
import '../../../lyrics/screens/lyrics_sync_screen.dart';

// ─── LRC Parser ──────────────────────────────────────────────────────────────

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

String _lrcSavePath(String audioPath) {
  final base = audioPath.replaceAll(
      RegExp(r'\.(mp3|flac|m4a)$', caseSensitive: false), '');
  return '$base.lrc';
}

// ─── Lyrics fetch: asset cache → lrclib.net → lyrics.ovh ────────────────────

Future<String?> _fetchLrcFromNet({
  required String title,
  String? artist,
  int? durationSeconds,
}) async {
  final assetHit = await _loadFromAssets(title);
  if (assetHit != null) return assetHit;
  final lrclibHit = await _fetchFromLrclib(
      title: title, artist: artist, durationSeconds: durationSeconds);
  if (lrclibHit != null) return lrclibHit;
  return _fetchFromLyricsOvh(title: title, artist: artist);
}

Future<String?> _loadFromAssets(String title) async {
  for (final path in [
    'assets/lyrics/$title.lrc',
    'assets/lyrics/$title.txt',
    'assets/lyrics/${title.replaceAll(' ', '_')}.lrc',
  ]) {
    try {
      final s = await rootBundle.loadString(path);
      if (s.trim().isNotEmpty) return s;
    } catch (_) {}
  }
  return null;
}

Future<String?> _fetchFromLrclib(
    {required String title, String? artist, int? durationSeconds}) async {
  const base = 'https://lrclib.net/api';
  Future<String?> q(Uri uri) async {
    try {
      final res = await http.get(uri, headers: {
        'User-Agent': 'Resonance/1.0'
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body);
      String? pick(Map e) {
        final s = e['syncedLyrics'] as String?;
        final p = e['plainLyrics'] as String?;
        return (s != null && s.isNotEmpty) ? s : p;
      }

      if (json is List) {
        if (json.isEmpty) return null;
        final synced = json.where((e) =>
            e['syncedLyrics'] != null &&
            (e['syncedLyrics'] as String).isNotEmpty);
        final best = synced.isNotEmpty ? synced.first : json.first;
        return pick(best as Map);
      } else if (json is Map) {
        return pick(json as Map);
      }
    } catch (_) {}
    return null;
  }

  if (artist != null && artist != 'Unknown Artist' && durationSeconds != null) {
    final r = await q(Uri.parse('$base/get').replace(queryParameters: {
      'track_name': title,
      'artist_name': artist,
      'duration': '$durationSeconds',
    }));
    if (r != null) return r;
  }
  if (artist != null && artist != 'Unknown Artist') {
    final r = await q(Uri.parse('$base/search').replace(queryParameters: {
      'track_name': title,
      'artist_name': artist,
    }));
    if (r != null) return r;
  }
  return q(Uri.parse('$base/search')
      .replace(queryParameters: {'track_name': title}));
}

Future<String?> _fetchFromLyricsOvh(
    {required String title, String? artist}) async {
  if (artist == null || artist == 'Unknown Artist') return null;
  try {
    final res = await http
        .get(Uri.parse(
            'https://api.lyrics.ovh/v1/${Uri.encodeComponent(artist)}/${Uri.encodeComponent(title)}'))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final body = res.body;
    final start = body.indexOf('"lyrics"');
    if (start < 0) return null;
    final q1 = body.indexOf('"', start + 9);
    final q2 = body.lastIndexOf('"');
    if (q1 < 0 || q2 <= q1) return null;
    final raw = body
        .substring(q1 + 1, q2)
        .replaceAll('\\n', '\n')
        .replaceAll('\\r', '')
        .trim();
    return raw.isNotEmpty ? raw : null;
  } catch (_) {
    return null;
  }
}

// ─── Main Screen ─────────────────────────────────────────────────────────────

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
                    child: Text('No playlists yet.',
                        style: TextStyle(color: Colors.white38)))
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

// ─── Player Tab ───────────────────────────────────────────────────────────────

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
    _pageCtrl.animateToPage(_showingLyrics ? 0 : 1,
        duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
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

      return Column(children: [
        Expanded(
          child: PageView(
            controller: _pageCtrl,
            onPageChanged: (i) => setState(() => _showingLyrics = i == 1),
            children: [
              _PlayerPage(
                  ctrl: widget.ctrl,
                  song: song,
                  meta: meta,
                  onAddToPlaylist: widget.onAddToPlaylist),
              // FIX-LYRICS-SONG-CHANGE: ValueKey forces full widget recreation
              // when song.path changes, so ScrollController resets to 0 and
              // stale lyrics state is discarded. Without this key, Flutter
              // reuses the old _LyricsPageState and tries to scroll to the
              // old song's active line index in the new (empty) scroll area.
              _LyricsPage(
                  key: ValueKey(song.path), ctrl: widget.ctrl, song: song),
            ],
          ),
        ),
        _SeekBar(ctrl: widget.ctrl),
        const SizedBox(height: 4),
        _Controls(ctrl: widget.ctrl),
        const SizedBox(height: 8),
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
                fontSize: 13),
          ),
        ),
        const SizedBox(height: 12),
      ]);
    });
  }
}

// ─── Player Page ──────────────────────────────────────────────────────────────

class _PlayerPage extends StatelessWidget {
  final PlayerController ctrl;
  final SongFile song;
  final SongMetadata? meta;
  final Function(String) onAddToPlaylist;
  const _PlayerPage(
      {required this.ctrl,
      required this.song,
      required this.meta,
      required this.onAddToPlaylist});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 16, 40, 8),
          child: Center(
            child: AspectRatio(
                aspectRatio: 1, child: _AlbumArtWidget(song: song, meta: meta)),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                style: const TextStyle(color: Colors.white60, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                meta?.customAlbum?.isNotEmpty == true
                    ? meta!.customAlbum!
                    : song.ext.toUpperCase(),
                style: const TextStyle(color: Colors.white38, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          IconButton(
            icon:
                const Icon(Icons.edit_rounded, color: Colors.white30, size: 20),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => EditMetadataSheet(song: song),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 16),
    ]);
  }
}

// ─── Album Art ────────────────────────────────────────────────────────────────

class _AlbumArtWidget extends StatelessWidget {
  final SongFile song;
  final SongMetadata? meta;
  const _AlbumArtWidget({required this.song, required this.meta});

  @override
  Widget build(BuildContext context) {
    final artPath = meta?.artImagePath;
    final hasArt = artPath != null && File(artPath).existsSync();
    return GestureDetector(
      onLongPress: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => EditMetadataSheet(song: song),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Container(
          key: ValueKey(artPath ?? 'placeholder'),
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
              ? Image.file(File(artPath!),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity)
              : Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.music_note_rounded,
                      color: AppTheme.primary, size: 80),
                  const SizedBox(height: 8),
                  Text('Long-press to add art',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.2), fontSize: 11)),
                ])),
        ),
      ),
    );
  }
}

// ─── Lyrics Page ──────────────────────────────────────────────────────────────

enum _LyricsState { idle, fetching, loaded, notFound, error }

class _LyricsPage extends StatefulWidget {
  final PlayerController ctrl;
  final SongFile song;
  // KEY IS SET BY PARENT: ValueKey(song.path) — see _PlayerTabState.build()
  const _LyricsPage({super.key, required this.ctrl, required this.song});

  @override
  State<_LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<_LyricsPage> {
  List<LrcLine> _lines = [];
  String? _plainText;
  _LyricsState _state = _LyricsState.idle;
  String? _loadedFor;
  bool _fetching = false;
  // ScrollController starts fresh on every widget creation (new song)
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    // Load immediately when the widget is created for this song
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(widget.song);
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(SongFile song) async {
    if (_loadedFor == song.path && _state == _LyricsState.loaded) return;
    if (_loadedFor == song.path && _fetching) return;
    _loadedFor = song.path;
    _lines = [];
    _plainText = null;
    _fetching = false;

    final localPath = _lrcPathFor(song.path);
    if (localPath != null) {
      _parseLocal(localPath);
      return;
    }

    if (!mounted) return;
    setState(() {
      _state = _LyricsState.fetching;
      _fetching = true;
    });

    try {
      String title = song.name;
      String? artist;
      int? durSecs;
      try {
        final m = Get.find<MetadataService>().get(song.path);
        if (m?.customTitle?.isNotEmpty == true) title = m!.customTitle!;
        if (m?.customArtist?.isNotEmpty == true) artist = m!.customArtist!;
      } catch (_) {}
      try {
        final d = Get.find<PlayerController>().duration.value;
        if (d.inSeconds > 0) durSecs = d.inSeconds;
      } catch (_) {}

      final content = await _fetchLrcFromNet(
          title: title, artist: artist, durationSeconds: durSecs);
      if (!mounted) return;

      if (content == null || content.trim().isEmpty) {
        setState(() {
          _state = _LyricsState.notFound;
          _fetching = false;
        });
        return;
      }

      try {
        await File(_lrcSavePath(song.path)).writeAsString(content);
      } catch (_) {}

      final parsed = parseLrc(content);
      setState(() {
        _fetching = false;
        if (parsed.isNotEmpty) {
          _lines = parsed;
        } else {
          _plainText = content.trim();
        }
        _state = _LyricsState.loaded;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _LyricsState.error;
        _fetching = false;
      });
    }
  }

  void _parseLocal(String path) {
    try {
      final content = File(path).readAsStringSync();
      final parsed = path.endsWith('.lrc') ? parseLrc(content) : <LrcLine>[];
      setState(() {
        if (parsed.isNotEmpty) {
          _lines = parsed;
        } else {
          _plainText = content.trim();
        }
        _state = _LyricsState.loaded;
        _fetching = false;
      });
    } catch (_) {
      setState(() {
        _state = _LyricsState.error;
        _fetching = false;
      });
    }
  }

  int _activeIdx(Duration pos) {
    if (_lines.isEmpty) return -1;
    int a = 0;
    for (int i = 0; i < _lines.length; i++) {
      if (_lines[i].time <= pos)
        a = i;
      else
        break;
    }
    return a;
  }

  void _autoScroll(int idx) {
    if (!_scrollCtrl.hasClients || idx < 0) return;
    if (!_scrollCtrl.position.hasContentDimensions) return;
    final t = (idx * 56.0) - (_scrollCtrl.position.viewportDimension / 2) + 28;
    _scrollCtrl.animateTo(t.clamp(0, _scrollCtrl.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  void _reset() {
    setState(() {
      _state = _LyricsState.idle;
      _loadedFor = null;
    });
    _load(widget.song);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Guard: only use lyrics that belong to the currently playing song.
      // This prevents race conditions where position from song A scrolls
      // lyrics of song B.
      final currentSong = widget.ctrl.currentSong;
      if (currentSong == null || currentSong.path != widget.song.path) {
        return const Center(
            child: CircularProgressIndicator(color: AppTheme.primary));
      }

      if (_state == _LyricsState.idle || _state == _LyricsState.fetching) {
        return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: AppTheme.primary),
          const SizedBox(height: 20),
          Text(
              _state == _LyricsState.fetching
                  ? 'Finding lyrics...'
                  : 'Loading...',
              style: const TextStyle(color: Colors.white38, fontSize: 14)),
        ]));
      }

      if (_state == _LyricsState.notFound) {
        return Center(
            child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lyrics_rounded, color: Colors.white12, size: 64),
            const SizedBox(height: 16),
            const Text('No lyrics found',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            const Text(
                'Couldn\'t find lyrics online.\nSync them in the Sync Studio.',
                style:
                    TextStyle(color: Colors.white24, fontSize: 13, height: 1.6),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () =>
                  Get.to(() => LyricsSyncScreen(song: widget.song)),
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Open Sync Studio'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh_rounded,
                  size: 16, color: AppTheme.primary),
              label: const Text('Try again',
                  style: TextStyle(color: AppTheme.primary)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.primary)),
            ),
          ]),
        ));
      }

      if (_state == _LyricsState.error) {
        return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.white24, size: 56),
          const SizedBox(height: 16),
          const Text('Couldn\'t load lyrics',
              style: TextStyle(color: Colors.white38, fontSize: 16)),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.refresh_rounded,
                size: 16, color: AppTheme.primary),
            label:
                const Text('Retry', style: TextStyle(color: AppTheme.primary)),
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.primary)),
          ),
        ]));
      }

      if (_lines.isEmpty && _plainText != null) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Text(_plainText!,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 16, height: 1.8)),
        );
      }

      final pos = widget.ctrl.position.value;
      final activeIdx = _activeIdx(pos);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _autoScroll(activeIdx));

      return ListView.builder(
        controller: _scrollCtrl,
        padding: EdgeInsets.symmetric(
            horizontal: 24, vertical: MediaQuery.of(context).size.height * 0.3),
        itemCount: _lines.length,
        itemBuilder: (_, i) {
          final isActive = i == activeIdx;
          final isPast = i < activeIdx;
          return GestureDetector(
            onTap: () => widget.ctrl.seek(_lines[i].time.inSeconds.toDouble()),
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
}

// ─── Seek Bar ─────────────────────────────────────────────────────────────────

class _SeekBar extends StatefulWidget {
  final PlayerController ctrl;
  const _SeekBar({required this.ctrl});
  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;
  String _fmt(Duration d) =>
      '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final dur = widget.ctrl.duration.value.inSeconds.toDouble();
      final pos = _drag ?? widget.ctrl.position.value.inSeconds.toDouble();
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
              onChangeStart: (v) => setState(() => _drag = v),
              onChanged: dur > 0 ? (v) => setState(() => _drag = v) : null,
              onChangeEnd: (v) {
                widget.ctrl.seek(v);
                setState(() => _drag = null);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      _fmt(_drag != null
                          ? Duration(seconds: _drag!.toInt())
                          : widget.ctrl.position.value),
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 12)),
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

// ─── Controls ─────────────────────────────────────────────────────────────────

class _Controls extends StatelessWidget {
  final PlayerController ctrl;
  const _Controls({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
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
                onPressed: ctrl.playPrev),
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
                onPressed: ctrl.playNext),
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
          ]),
        ));
  }
}

// ─── Queue Tab ────────────────────────────────────────────────────────────────
//
// FIX-QUEUE-SHUFFLE-ORDER: When shuffle is enabled, the list is reordered to
// show the shuffle sequence instead of the raw alphabetical queue.
// Layout: [current song at top] → [upcoming in shuffle order] → [already played, greyed]
//
// FIX-QUEUE-OVERFLOW: Flexible + ellipsis on the header text.
//
// FIX-QUEUE-SCROLL-RETRIGGER: Removed _lastScrolledTo guard so scroll fires
// every time the Obx rebuilds (which only happens when queueIndex or queue changes).

class _QueueTab extends StatefulWidget {
  final PlayerController ctrl;
  const _QueueTab({required this.ctrl});

  @override
  State<_QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends State<_QueueTab> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  // FIX-QUEUE-SCROLL-RETRIGGER: removed _lastScrolledTo check.
  // This now fires on every queueIndex change, which is exactly when we want it.
  void _scrollToCurrentSong(int idx) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      if (!_scrollCtrl.position.hasContentDimensions) return;
      const itemHeight = 68.0;
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
      final ctrl = widget.ctrl;
      if (ctrl.queue.isEmpty) {
        return const Center(
            child: Text('Queue is empty',
                style: TextStyle(color: Colors.white38)));
      }

      final isShuffle = ctrl.shuffleEnabled.value;
      final currentQueueIdx = ctrl.queueIndex.value;
      final currentSong =
          currentQueueIdx >= 0 && currentQueueIdx < ctrl.queue.length
              ? ctrl.queue[currentQueueIdx]
              : null;

      // FIX-QUEUE-SHUFFLE-ORDER:
      // Build a display list that reflects actual playback order.
      // Each entry: (songFile, originalQueueIndex, isPlayed)
      final List<({SongFile song, int queueIdx, bool isPlayed})> displayList;

      if (isShuffle && ctrl.shuffleOrder.isNotEmpty) {
        // shuffleOrder[0..shufflePos] = played (including current at shufflePos)
        // shuffleOrder[shufflePos+1..end] = upcoming
        final order = ctrl.shuffleOrder;
        final pos = ctrl.shufflePos;
        displayList = [
          // Current song first (pos in shuffleOrder)
          if (pos < order.length && order[pos] < ctrl.queue.length)
            (
              song: ctrl.queue[order[pos]],
              queueIdx: order[pos],
              isPlayed: false
            ),
          // Upcoming songs in shuffle order
          for (int i = pos + 1; i < order.length; i++)
            if (order[i] < ctrl.queue.length)
              (song: ctrl.queue[order[i]], queueIdx: order[i], isPlayed: false),
          // Already-played songs (before pos, greyed out)
          for (int i = pos - 1; i >= 0; i--)
            if (order[i] < ctrl.queue.length)
              (song: ctrl.queue[order[i]], queueIdx: order[i], isPlayed: true),
        ];
      } else {
        // Normal order — just show queue as-is
        displayList = [
          for (int i = 0; i < ctrl.queue.length; i++)
            (song: ctrl.queue[i], queueIdx: i, isPlayed: i < currentQueueIdx),
        ];
      }

      // In normal mode, the current song's display index = currentQueueIdx.
      // In shuffle mode, it's always index 0 in our display list.
      final displayCurrentIdx =
          isShuffle && ctrl.shuffleOrder.isNotEmpty ? 0 : currentQueueIdx;
      _scrollToCurrentSong(displayCurrentIdx);

      return Column(children: [
        // FIX-QUEUE-OVERFLOW: Flexible wraps the long text so it can't overflow
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(children: [
            Flexible(
              child: Text(
                '${ctrl.queue.length} songs · ${ctrl.queueSource.value}'
                '${isShuffle ? ' · Shuffle' : ''}',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            if (!isShuffle)
              const Text('Hold to reorder',
                  style: TextStyle(color: Colors.white24, fontSize: 12)),
          ]),
        ),

        Expanded(
          child: isShuffle
              // In shuffle mode: plain ListView (shuffle order can't be manually reordered)
              ? ListView.builder(
                  controller: _scrollCtrl,
                  itemCount: displayList.length,
                  itemExtent: 68,
                  itemBuilder: (_, i) {
                    final entry = displayList[i];
                    final isCurrent = i == 0 && ctrl.shuffleOrder.isNotEmpty;
                    return _queueTile(
                      song: entry.song,
                      displayIndex: i,
                      queueIdx: entry.queueIdx,
                      isCurrent: isCurrent,
                      isPlayed: entry.isPlayed,
                      ctrl: ctrl,
                    );
                  },
                )
              // In normal mode: reorderable list
              : ReorderableListView.builder(
                  scrollController: _scrollCtrl,
                  itemCount: displayList.length,
                  onReorder: ctrl.reorderQueue,
                  proxyDecorator: (child, _, __) =>
                      Material(color: Colors.transparent, child: child),
                  itemBuilder: (_, i) {
                    final entry = displayList[i];
                    final isCurrent = entry.queueIdx == currentQueueIdx;
                    return _queueTile(
                      key: ValueKey(entry.song.path + i.toString()),
                      song: entry.song,
                      displayIndex: i,
                      queueIdx: entry.queueIdx,
                      isCurrent: isCurrent,
                      isPlayed: entry.isPlayed,
                      ctrl: ctrl,
                    );
                  },
                ),
        ),
      ]);
    });
  }

  Widget _queueTile({
    Key? key,
    required SongFile song,
    required int displayIndex,
    required int queueIdx,
    required bool isCurrent,
    required bool isPlayed,
    required PlayerController ctrl,
  }) {
    return SizedBox(
      key: key ?? ValueKey(song.path + displayIndex.toString()),
      height: 68,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isCurrent
                ? AppTheme.primary.withOpacity(0.2)
                : isPlayed
                    ? Colors.white.withOpacity(0.03)
                    : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: isCurrent && ctrl.isPlaying.value
              ? const Icon(Icons.equalizer_rounded,
                  color: AppTheme.primary, size: 16)
              : Center(
                  child: Text('${displayIndex + 1}',
                      style: TextStyle(
                          color: isCurrent
                              ? AppTheme.primary
                              : isPlayed
                                  ? Colors.white12
                                  : Colors.white30,
                          fontSize: 12,
                          fontWeight: FontWeight.bold))),
        ),
        title: Text(song.name,
            style: TextStyle(
              color: isCurrent
                  ? AppTheme.primary
                  : isPlayed
                      ? Colors.white24
                      : Colors.white,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(song.ext.toUpperCase(),
            style: TextStyle(
                color: isPlayed ? Colors.white12 : Colors.white24,
                fontSize: 11)),
        trailing: isCurrent
            ? const Icon(Icons.volume_up_rounded,
                color: AppTheme.primary, size: 16)
            : IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white24, size: 18),
                onPressed: () => ctrl.removeFromQueue(queueIdx),
                padding: EdgeInsets.zero,
              ),
        onTap: () => ctrl.playByQueueIndex(queueIdx),
      ),
    );
  }
}

// ─── Edit Metadata Sheet ──────────────────────────────────────────────────────

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
      final xfile = await ImagePicker().pickImage(source: ImageSource.gallery);
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
      await svc.save(SongMetadata(
        filePath: widget.song.path,
        customTitle:
            _titleCtrl.text.trim().isNotEmpty ? _titleCtrl.text.trim() : null,
        customArtist:
            _artistCtrl.text.trim().isNotEmpty ? _artistCtrl.text.trim() : null,
        customAlbum:
            _albumCtrl.text.trim().isNotEmpty ? _albumCtrl.text.trim() : null,
        artImagePath: _artPath,
      ));
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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

  Widget _field(TextEditingController c, String label, String hint) =>
      TextField(
        controller: c,
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
              borderSide:
                  const BorderSide(color: AppTheme.primary, width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );
}
