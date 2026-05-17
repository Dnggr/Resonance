// lib/features/player/screens/now_playing_screen.dart
//
// FIX LOG (this session):
//  [FIX-ART-SQUARE]   Album art container uses AspectRatio(1) — always square.
//  [FIX-QUEUE-SCROLL] Queue tab auto-scrolls to currently playing song.
//  [FEAT-LYRICS]      Spotify-style lyrics: PageView swipe or Lyrics button.
//                     Auto-fetches synced .lrc from lrclib.net when no local
//                     file exists. Saves to disk so it works offline after
//                     first fetch. Karaoke highlighting + auto-scroll.
//  [FIX-LYRICS-FALLBACK] Multi-API waterfall: asset cache → lrclib.net →
//                     lyrics.ovh. Better coverage for Tagalog/OPM songs.

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

/// Returns existing local lyrics path (.lrc preferred over .txt), or null.
String? _lrcPathFor(String audioPath) {
  final base = audioPath.replaceAll(
      RegExp(r'\.(mp3|flac|m4a)$', caseSensitive: false), '');
  final lrc = '$base.lrc';
  if (File(lrc).existsSync()) return lrc;
  final txt = '$base.txt';
  if (File(txt).existsSync()) return txt;
  return null;
}

/// Returns the path where a fetched .lrc should be saved (next to the audio).
String _lrcSavePath(String audioPath) {
  final base = audioPath.replaceAll(
      RegExp(r'\.(mp3|flac|m4a)$', caseSensitive: false), '');
  return '$base.lrc';
}

// ─── Lyrics Fetch: asset cache → lrclib.net → lyrics.ovh ────────────────────
// Waterfall:
//   1. assets/lyrics/<title>.lrc  (instant, offline, bundled in app)
//   2. lrclib.net                 (synced LRC preferred, plain fallback)
//   3. lyrics.ovh                 (plain text, better for Tagalog/OPM)
Future<String?> _fetchLrcFromNet({
  required String title,
  String? artist,
  int? durationSeconds,
}) async {
  // Step 0: bundled asset cache (instant, offline)
  final assetResult = await _loadFromAssets(title);
  if (assetResult != null) return assetResult;

  // Step 1+2: lrclib.net (synced preferred, plain fallback)
  final lrclibResult = await _fetchFromLrclib(
    title: title,
    artist: artist,
    durationSeconds: durationSeconds,
  );
  if (lrclibResult != null) return lrclibResult;

  // Step 3: lyrics.ovh (plain text, better for Tagalog/OPM)
  return _fetchFromLyricsOvh(title: title, artist: artist);
}

/// Check bundled assets/lyrics/<title>.lrc before any network call.
/// To use: create assets/lyrics/ folder, add to pubspec.yaml assets:,
/// and place files like "Pasilyo.lrc", "Alipin.lrc" etc. there.
Future<String?> _loadFromAssets(String title) async {
  final candidates = [
    'assets/lyrics/$title.lrc',
    'assets/lyrics/$title.txt',
    'assets/lyrics/${title.replaceAll(' ', '_')}.lrc',
  ];
  for (final assetPath in candidates) {
    try {
      final content = await rootBundle.loadString(assetPath);
      if (content.trim().isNotEmpty) return content;
    } catch (_) {}
  }
  return null;
}

/// lrclib.net — synced LRC preferred, plain text fallback.
Future<String?> _fetchFromLrclib({
  required String title,
  String? artist,
  int? durationSeconds,
}) async {
  const base = 'https://lrclib.net/api';

  Future<String?> tryQuery(Uri uri) async {
    try {
      final res = await http.get(uri, headers: {
        'User-Agent': 'Resonance/1.0'
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body);

      if (json is List) {
        if (json.isEmpty) return null;
        final withSynced = json
            .where((e) =>
                e['syncedLyrics'] != null &&
                (e['syncedLyrics'] as String).isNotEmpty)
            .toList();
        final pick = withSynced.isNotEmpty ? withSynced.first : json.first;
        final synced = pick['syncedLyrics'] as String?;
        final plain = pick['plainLyrics'] as String?;
        return (synced != null && synced.isNotEmpty) ? synced : plain;
      } else if (json is Map) {
        final synced = json['syncedLyrics'] as String?;
        final plain = json['plainLyrics'] as String?;
        return (synced != null && synced.isNotEmpty) ? synced : plain;
      }
    } catch (_) {}
    return null;
  }

  // Most precise: title + artist + duration
  if (artist != null && artist != 'Unknown Artist' && durationSeconds != null) {
    final r = await tryQuery(Uri.parse('$base/get').replace(queryParameters: {
      'track_name': title,
      'artist_name': artist,
      'duration': '$durationSeconds',
    }));
    if (r != null) return r;
  }

  // Title + artist search
  if (artist != null && artist != 'Unknown Artist') {
    final r =
        await tryQuery(Uri.parse('$base/search').replace(queryParameters: {
      'track_name': title,
      'artist_name': artist,
    }));
    if (r != null) return r;
  }

  // Title only fallback
  return tryQuery(Uri.parse('$base/search')
      .replace(queryParameters: {'track_name': title}));
}

/// lyrics.ovh — plain text, better coverage for Tagalog/OPM content.
Future<String?> _fetchFromLyricsOvh({
  required String title,
  String? artist,
}) async {
  final effectiveArtist =
      (artist != null && artist != 'Unknown Artist') ? artist : null;
  if (effectiveArtist == null) return null;

  try {
    final uri = Uri.parse(
        'https://api.lyrics.ovh/v1/${Uri.encodeComponent(effectiveArtist)}/${Uri.encodeComponent(title)}');
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
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

  // State machine for loading
  // idle → loading → loaded | error | notFound
  _LyricsState _state = _LyricsState.idle;
  String? _loadedFor; // audio path that was loaded
  bool _fetching = false; // true while network request is in flight

  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  // Called when the song changes or when the user taps "Try again"
  Future<void> _load(SongFile song) async {
    // Don't reload if we already have lyrics for this exact file
    if (_loadedFor == song.path && _state == _LyricsState.loaded) return;
    // Don't double-fetch
    if (_loadedFor == song.path && _fetching) return;

    _loadedFor = song.path;
    _lines = [];
    _plainText = null;
    _fetching = false;

    // ── Step 1: Check for a local .lrc / .txt file ───────────────────────
    final localPath = _lrcPathFor(song.path);
    if (localPath != null) {
      _parseAndSetLocal(localPath);
      return;
    }

    // ── Step 2: No local file → fetch from network ────────────────────
    if (!mounted) return;
    setState(() {
      _state = _LyricsState.fetching;
      _fetching = true;
    });

    try {
      // Get title and artist from metadata if available
      String title = song.name;
      String? artist;
      int? durationSecs;
      try {
        final meta = Get.find<MetadataService>().get(song.path);
        if (meta?.customTitle?.isNotEmpty == true) title = meta!.customTitle!;
        if (meta?.customArtist?.isNotEmpty == true)
          artist = meta!.customArtist!;
      } catch (_) {}
      try {
        final ctrl = Get.find<PlayerController>();
        final dur = ctrl.duration.value;
        if (dur.inSeconds > 0) durationSecs = dur.inSeconds;
      } catch (_) {}

      final lrcContent = await _fetchLrcFromNet(
        title: title,
        artist: artist,
        durationSeconds: durationSecs,
      );

      if (!mounted) return;

      if (lrcContent == null || lrcContent.trim().isEmpty) {
        setState(() {
          _state = _LyricsState.notFound;
          _fetching = false;
        });
        return;
      }

      // Save to disk next to the audio so it works offline next time
      final savePath = _lrcSavePath(song.path);
      try {
        await File(savePath).writeAsString(lrcContent);
      } catch (_) {
        // Non-fatal: still display lyrics in memory
      }

      // Parse and display
      final parsed = parseLrc(lrcContent);
      setState(() {
        _fetching = false;
        if (parsed.isNotEmpty) {
          _lines = parsed;
          _state = _LyricsState.loaded;
        } else {
          // returned plain text (no timestamps)
          _plainText = lrcContent.trim();
          _state = _LyricsState.loaded;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _LyricsState.error;
        _fetching = false;
      });
    }
  }

  void _parseAndSetLocal(String localPath) {
    try {
      final content = File(localPath).readAsStringSync();
      final parsed =
          localPath.endsWith('.lrc') ? parseLrc(content) : <LrcLine>[];
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
      if (song == null) {
        return const Center(
            child: Text('Nothing playing',
                style: TextStyle(color: Colors.white38)));
      }

      // Trigger load when song changes (side-effect inside Obx is safe here
      // because _load is idempotent for the same song path)
      if (_loadedFor != song.path) {
        // Schedule after build so setState is not called during build
        WidgetsBinding.instance.addPostFrameCallback((_) => _load(song));
      }

      // ── Fetching ────────────────────────────────────────────────────────
      if (_state == _LyricsState.idle || _state == _LyricsState.fetching) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: AppTheme.primary),
            const SizedBox(height: 20),
            Text(
              _state == _LyricsState.fetching
                  ? 'Finding lyrics...'
                  : 'Loading...',
              style: const TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ]),
        );
      }

      // ── Not found ────────────────────────────────────────────────────────
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
              Text(
                'Couldn\'t find lyrics for this song online.\n'
                'You can add a .lrc or .txt file with the same name as your audio file.',
                style: const TextStyle(
                    color: Colors.white24, fontSize: 13, height: 1.6),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _state = _LyricsState.idle;
                    _loadedFor = null;
                  });
                  _load(song);
                },
                icon: const Icon(Icons.refresh_rounded,
                    size: 16, color: AppTheme.primary),
                label: const Text('Try again',
                    style: TextStyle(color: AppTheme.primary)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.primary)),
              ),
            ]),
          ),
        );
      }

      // ── Error ────────────────────────────────────────────────────────────
      if (_state == _LyricsState.error) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white24, size: 56),
            const SizedBox(height: 16),
            const Text('Couldn\'t load lyrics',
                style: TextStyle(color: Colors.white38, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Check your connection and try again.',
                style: TextStyle(color: Colors.white24, fontSize: 13)),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _state = _LyricsState.idle;
                  _loadedFor = null;
                });
                _load(song);
              },
              icon: const Icon(Icons.refresh_rounded,
                  size: 16, color: AppTheme.primary),
              label: const Text('Retry',
                  style: TextStyle(color: AppTheme.primary)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.primary)),
            ),
          ]),
        );
      }

      // ── Loaded: plain text ───────────────────────────────────────────────
      if (_lines.isEmpty && _plainText != null) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Text(_plainText!,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 16, height: 1.8)),
        );
      }

      // ── Loaded: synced LRC karaoke ────────────────────────────────────────
      final pos = widget.ctrl.position.value;
      final activeIdx = _activeIndex(pos);

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

enum _LyricsState { idle, fetching, loaded, notFound, error }

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
