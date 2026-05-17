// lib/features/lyrics/screens/lyrics_sync_screen.dart
//
// FEATURE: In-App Lyric Sync Studio ("Resonance Sync Studio")
//
// Workflow:
//   1. User pastes plain-text lyrics into a text field (or fetches from lyrics.ovh).
//   2. Taps "Start Syncing" — enters Sync Mode.
//   3. Song plays. Each time the singer starts a line, the user taps the
//      highlighted line row (or the big "Stamp this line" button).
//   4. Flutter captures player.position at that exact millisecond.
//   5. After all lines are stamped, user taps "Save .lrc".
//   6. The app writes a standard .lrc file next to the audio file.
//      Next time that song plays and Lyrics is opened, it loads instantly offline.
//
// UX extras implemented:
//   • Rewind 5 seconds button
//   • Currently-pending line is highlighted in bold purple
//   • Fine-tune: after syncing, tap any line to adjust its timestamp ±100ms
//   • Fetch plain-text lyrics from lyrics.ovh (free, no key) as a starting point

// lib/features/lyrics/screens/lyrics_sync_screen.dart
//
// FEATURE: In-App Lyric Sync Studio ("Resonance Sync Studio")
// ...

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../../../core/theme/app_theme.dart';
import '../../features/player/controllers/player_controller.dart'; // ← FIXED

// ─── helpers ────────────────────────────────────────────────────────────────

String _formatLrcTime(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final cs =
      (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
  return '[$m:$s.$cs]';
}

String _buildLrcContent(List<_SyncLine> lines) {
  final buf = StringBuffer();
  for (final line in lines) {
    if (line.timestamp != null) {
      buf.writeln('${_formatLrcTime(line.timestamp!)}${line.text}');
    }
  }
  return buf.toString();
}

String? _lrcSavePath(String audioPath) {
  final base = audioPath.replaceAll(
      RegExp(r'\.(mp3|flac|m4a)$', caseSensitive: false), '');
  return '$base.lrc';
}

// ─── data model ─────────────────────────────────────────────────────────────

class _SyncLine {
  String text;
  Duration? timestamp;
  _SyncLine(this.text);
}

// ─── screen ─────────────────────────────────────────────────────────────────

class LyricsSyncScreen extends StatefulWidget {
  final SongFile song;
  const LyricsSyncScreen({super.key, required this.song});

  @override
  State<LyricsSyncScreen> createState() => _LyricsSyncScreenState();
}

class _LyricsSyncScreenState extends State<LyricsSyncScreen> {
  // ── Phase ─────────────────────────────────────────────────────────────────
  // 'input'  → user pastes lyrics
  // 'sync'   → song plays, user taps to stamp
  // 'review' → all stamped, user can fine-tune then save
  String _phase = 'input';

  // ── State ─────────────────────────────────────────────────────────────────
  final TextEditingController _lyricsInput = TextEditingController();
  List<_SyncLine> _lines = [];
  int _currentLineIdx = 0; // which line is next to be stamped
  bool _fetching = false;
  final ScrollController _syncScroll = ScrollController();

  PlayerController get _ctrl => Get.find<PlayerController>();

  @override
  void dispose() {
    _lyricsInput.dispose();
    _syncScroll.dispose();
    super.dispose();
  }

  // ── Fetch plain-text lyrics from lyrics.ovh ──────────────────────────────
  Future<void> _fetchLyricsFromOvh() async {
    setState(() => _fetching = true);
    try {
      // Parse title and artist from song name or metadata
      String title = widget.song.name;
      String artist = 'Unknown';
      try {
        final svc = Get.find();
        final m = svc.get(widget.song.path);
        if (m?.customTitle?.isNotEmpty == true) title = m!.customTitle!;
        if (m?.customArtist?.isNotEmpty == true) artist = m!.customArtist!;
      } catch (_) {}

      final uri = Uri.parse(
          'https://api.lyrics.ovh/v1/${Uri.encodeComponent(artist)}/${Uri.encodeComponent(title)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = res.body;
        // lyrics.ovh returns JSON: {"lyrics": "..."}
        final start = body.indexOf('"lyrics"');
        if (start >= 0) {
          final q1 = body.indexOf('"', start + 9);
          final q2 = body.lastIndexOf('"');
          if (q1 >= 0 && q2 > q1) {
            final raw = body
                .substring(q1 + 1, q2)
                .replaceAll('\\n', '\n')
                .replaceAll('\\r', '')
                .trim();
            if (raw.isNotEmpty) {
              setState(() => _lyricsInput.text = raw);
              return;
            }
          }
        }
      }
      _snack('Lyrics not found online. Paste them manually.');
    } catch (_) {
      _snack('Network error. Paste lyrics manually.');
    } finally {
      setState(() => _fetching = false);
    }
  }

  // ── Start syncing ─────────────────────────────────────────────────────────
  void _startSyncing() {
    final raw = _lyricsInput.text.trim();
    if (raw.isEmpty) {
      _snack('Paste or fetch lyrics first.');
      return;
    }
    final parsed = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) => _SyncLine(l))
        .toList();
    if (parsed.isEmpty) {
      _snack('No lines found.');
      return;
    }
    setState(() {
      _lines = parsed;
      _currentLineIdx = 0;
      _phase = 'sync';
    });
    // Start playing from beginning
    _ctrl.seek(0);
    if (!_ctrl.isPlaying.value) _ctrl.togglePlay();
  }

  // ── Stamp current line at player.position ────────────────────────────────
  void _stampCurrentLine() {
    if (_currentLineIdx >= _lines.length) return;
    final pos = _ctrl.position.value;
    setState(() {
      _lines[_currentLineIdx].timestamp = pos;
      _currentLineIdx++;
    });
    _scrollToCurrentLine();
    if (_currentLineIdx >= _lines.length) {
      // All lines stamped → review phase
      _ctrl.togglePlay(); // pause
      setState(() => _phase = 'review');
    }
  }

  // ── Rewind 5 seconds ──────────────────────────────────────────────────────
  void _rewind5() {
    final pos = _ctrl.position.value;
    final newPos = pos.inSeconds > 5 ? pos.inSeconds - 5 : 0;
    _ctrl.seek(newPos.toDouble());
    // Also undo last stamp if user missed a line
    if (_currentLineIdx > 0) {
      setState(() {
        _currentLineIdx--;
        _lines[_currentLineIdx].timestamp = null;
      });
    }
  }

  void _scrollToCurrentLine() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_syncScroll.hasClients) return;
      final target = (_currentLineIdx * 60.0) -
          (_syncScroll.position.viewportDimension / 2) +
          30;
      _syncScroll.animateTo(
        target.clamp(0, _syncScroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ── Fine-tune: adjust timestamp by delta ms ───────────────────────────────
  void _adjustTimestamp(int lineIdx, int deltaMs) {
    final t = _lines[lineIdx].timestamp;
    if (t == null) return;
    final newMs =
        (t.inMilliseconds + deltaMs).clamp(0, double.maxFinite.toInt());
    setState(() {
      _lines[lineIdx].timestamp = Duration(milliseconds: newMs);
    });
  }

  // ── Save .lrc file ────────────────────────────────────────────────────────
  Future<void> _saveLrc() async {
    final stamped = _lines.where((l) => l.timestamp != null).toList();
    if (stamped.isEmpty) {
      _snack('No lines stamped yet.');
      return;
    }
    final lrcContent = _buildLrcContent(_lines);
    final savePath = _lrcSavePath(widget.song.path);
    if (savePath == null) {
      _snack('Cannot determine save path for this song.');
      return;
    }
    try {
      await File(savePath).writeAsString(lrcContent);
      _snack('Lyrics saved! ✓ Open Now Playing → Lyrics to see them.');
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Get.back();
    } catch (e) {
      _snack('Save failed: $e');
    }
  }

  void _snack(String msg) {
    Get.snackbar('Sync Studio', msg,
        backgroundColor: AppTheme.surface,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
        snackPosition: SnackPosition.BOTTOM);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sync Studio',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          Text(widget.song.name,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ]),
        actions: [
          if (_phase == 'review')
            TextButton.icon(
              onPressed: _saveLrc,
              icon: const Icon(Icons.save_rounded,
                  color: AppTheme.primary, size: 18),
              label: const Text('Save .lrc',
                  style: TextStyle(
                      color: AppTheme.primary, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: switch (_phase) {
        'input' => _buildInputPhase(),
        'sync' => _buildSyncPhase(),
        'review' => _buildReviewPhase(),
        _ => const SizedBox.shrink(),
      },
    );
  }

  // ── Phase 1: Input ────────────────────────────────────────────────────────

  Widget _buildInputPhase() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        // Instructions
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
          ),
          child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How to sync lyrics',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                SizedBox(height: 6),
                Text(
                  '1. Paste plain lyrics below (or fetch them automatically)\n'
                  '2. Tap "Start Syncing"\n'
                  '3. The song plays — tap each line exactly when the singer says it\n'
                  '4. Review & fine-tune, then save',
                  style: TextStyle(
                      color: Colors.white54, fontSize: 12, height: 1.6),
                ),
              ]),
        ),
        const SizedBox(height: 16),

        // Fetch button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _fetching ? null : _fetchLyricsFromOvh,
            icon: _fetching
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primary))
                : const Icon(Icons.download_rounded,
                    color: AppTheme.primary, size: 18),
            label: Text(
              _fetching ? 'Fetching...' : 'Auto-fetch lyrics (lyrics.ovh)',
              style: const TextStyle(color: AppTheme.primary),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.primary),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Paste area
        Expanded(
          child: TextField(
            controller: _lyricsInput,
            style:
                const TextStyle(color: Colors.white, fontSize: 14, height: 1.7),
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              hintText:
                  'Paste plain lyrics here...\n\nOne line per lyric line.\nExample:\nLike I\'m gonna lose you\nI\'m gonna love you',
              hintStyle: const TextStyle(
                  color: Colors.white24, fontSize: 13, height: 1.7),
              filled: true,
              fillColor: AppTheme.surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 1.5)),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),
        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _startSyncing,
            icon: const Icon(Icons.play_arrow_rounded, size: 22),
            label: const Text('Start Syncing',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Phase 2: Sync ────────────────────────────────────────────────────────

  Widget _buildSyncPhase() {
    return Column(children: [
      // Progress indicator
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
        child: Row(children: [
          Text(
            '$_currentLineIdx / ${_lines.length} lines synced',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const Spacer(),
          Obx(() {
            final pos = _ctrl.position.value;
            final m = pos.inMinutes.remainder(60).toString().padLeft(2, '0');
            final s = pos.inSeconds.remainder(60).toString().padLeft(2, '0');
            return Text('$m:$s',
                style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold));
          }),
        ]),
      ),
      LinearProgressIndicator(
        value: _lines.isEmpty ? 0 : _currentLineIdx / _lines.length,
        backgroundColor: Colors.white10,
        color: AppTheme.primary,
        minHeight: 2,
      ),

      // Lyric lines list
      Expanded(
        child: ListView.builder(
          controller: _syncScroll,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          itemCount: _lines.length,
          itemExtent: 60,
          itemBuilder: (_, i) {
            final isPast = i < _currentLineIdx;
            final isCurrent = i == _currentLineIdx;
            return GestureDetector(
              onTap: isCurrent ? _stampCurrentLine : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? AppTheme.primary.withOpacity(0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: isCurrent
                      ? Border.all(color: AppTheme.primary.withOpacity(0.5))
                      : null,
                ),
                child: Row(children: [
                  if (isPast) ...[
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.greenAccent, size: 16),
                    const SizedBox(width: 8),
                  ] else if (isCurrent) ...[
                    const Icon(Icons.touch_app_rounded,
                        color: AppTheme.primary, size: 16),
                    const SizedBox(width: 8),
                  ] else ...[
                    const SizedBox(width: 24),
                  ],
                  Expanded(
                    child: Text(
                      _lines[i].text,
                      style: TextStyle(
                        color: isCurrent
                            ? Colors.white
                            : isPast
                                ? Colors.white38
                                : Colors.white54,
                        fontSize: isCurrent ? 15 : 13,
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isPast && _lines[i].timestamp != null)
                    Text(
                      _formatLrcTime(_lines[i].timestamp!),
                      style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 10,
                          fontFamily: 'monospace'),
                    ),
                ]),
              ),
            );
          },
        ),
      ),

      // Stamp button + rewind
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(children: [
            // Big stamp button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    _currentLineIdx < _lines.length ? _stampCurrentLine : null,
                icon: const Icon(Icons.touch_app_rounded, size: 22),
                label: Text(
                  _currentLineIdx < _lines.length
                      ? 'Tap when singer says: "${_lines[_currentLineIdx].text}"'
                      : 'All lines stamped!',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _rewind5,
                  icon: const Icon(Icons.replay_5_rounded,
                      color: Colors.white54, size: 18),
                  label: const Text('Rewind 5s & undo',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Obx(() => OutlinedButton.icon(
                    onPressed: _ctrl.togglePlay,
                    icon: Icon(
                      _ctrl.isPlaying.value
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white54,
                      size: 18,
                    ),
                    label: Text(
                      _ctrl.isPlaying.value ? 'Pause' : 'Play',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 16),
                    ),
                  )),
            ]),
          ]),
        ),
      ),
    ]);
  }

  // ── Phase 3: Review & Fine-tune ──────────────────────────────────────────

  Widget _buildReviewPhase() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: Row(children: [
          const Icon(Icons.check_circle_rounded,
              color: Colors.greenAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'All ${_lines.length} lines synced. Fine-tune below, then tap Save.',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          itemCount: _lines.length,
          itemBuilder: (_, i) {
            final line = _lines[i];
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Row(children: [
                // Line text
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(line.text,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          line.timestamp != null
                              ? _formatLrcTime(line.timestamp!)
                              : '(not stamped)',
                          style: TextStyle(
                            color: line.timestamp != null
                                ? AppTheme.primary
                                : AppTheme.accent,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ]),
                ),

                // Fine-tune controls: − 100ms / + 100ms
                if (line.timestamp != null) ...[
                  GestureDetector(
                    onTap: () => _adjustTimestamp(i, -100),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.remove_rounded,
                          color: Colors.white54, size: 14),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text('100ms',
                      style: TextStyle(color: Colors.white24, fontSize: 10)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _adjustTimestamp(i, 100),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.add_rounded,
                          color: Colors.white54, size: 14),
                    ),
                  ),
                ],
              ]),
            );
          },
        ),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveLrc,
              icon: const Icon(Icons.save_rounded, size: 20),
              label: const Text('Save .lrc File',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
