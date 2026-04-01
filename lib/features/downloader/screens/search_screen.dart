import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/theme/app_theme.dart';
import '../services/downloader_service.dart';
import 'downloads_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final DownloaderService _svc = Get.find<DownloaderService>();
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildSearchBar(),
            const SizedBox(height: 8),
            _buildResults(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Search',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5)),
                Text('Find & download audio',
                    style: TextStyle(color: Colors.white38, fontSize: 13)),
              ],
            ),
          ),
          // Downloads button with badge
          Obx(() {
            final active = _svc.activeDownloads.length;
            final completed = _svc.completedDownloads.length;
            final total = active + completed;
            return GestureDetector(
              onTap: () => Get.to(() => const DownloadsScreen()),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: active > 0
                        ? AppTheme.primary.withOpacity(0.6)
                        : Colors.white10,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (active > 0)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.primary),
                      )
                    else
                      const Icon(Icons.download_done_rounded,
                          color: Colors.white54, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      active > 0
                          ? '$active downloading'
                          : total > 0
                              ? '$total saved'
                              : 'Downloads',
                      style: TextStyle(
                        color: active > 0 ? AppTheme.primary : Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Artist, song, album...',
                hintStyle: const TextStyle(color: Colors.white30),
                prefixIcon:
                    const Icon(Icons.search_rounded, color: Colors.white38),
                suffixIcon: Obx(() => _svc.isSearching.value
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.primary),
                        ))
                    : _ctrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                color: Colors.white38, size: 18),
                            onPressed: () {
                              _ctrl.clear();
                              _svc.searchResults.clear();
                              setState(() {});
                            },
                          )
                        : const SizedBox.shrink()),
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.white10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: _svc.searchMusic,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _svc.searchMusic(_ctrl.text),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.search_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    return Expanded(
      child: Obx(() {
        if (_svc.searchError.value.isNotEmpty) {
          return _empty(Icons.wifi_off_rounded, _svc.searchError.value,
              color: AppTheme.accent);
        }
        if (_svc.isSearching.value && _svc.searchResults.isEmpty) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary));
        }
        if (_svc.searchResults.isEmpty) {
          return _empty(Icons.music_note_rounded, 'Search for music above');
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          itemCount: _svc.searchResults.length,
          itemBuilder: (_, i) =>
              _SearchResultTile(video: _svc.searchResults[i]),
        );
      }),
    );
  }

  Widget _empty(IconData icon, String msg, {Color? color}) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 56, color: color ?? Colors.white12),
        const SizedBox(height: 12),
        Text(msg,
            style: TextStyle(color: color ?? Colors.white30, fontSize: 14),
            textAlign: TextAlign.center),
      ]),
    );
  }
}

// ─── Search Result Tile ───────────────────────────────────────
class _SearchResultTile extends StatelessWidget {
  final dynamic video;
  const _SearchResultTile({required this.video});

  @override
  Widget build(BuildContext context) {
    final svc = Get.find<DownloaderService>();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                video.thumbnails.lowResUrl,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 56,
                  height: 56,
                  color: Colors.white10,
                  child: const Icon(Icons.music_note,
                      color: Colors.white30, size: 24),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(video.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(
                    '${video.author} · ${_dur(video.duration)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Download format picker
            _FormatPicker(
              onSelected: (fmt) => svc.queueDownload(video, fmt),
            ),
          ],
        ),
      ),
    );
  }

  String _dur(Duration? d) {
    if (d == null) return '--:--';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }
}

class _FormatPicker extends StatelessWidget {
  final Function(DownloadFormat) onSelected;
  const _FormatPicker({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<DownloadFormat>(
      tooltip: 'Choose format',
      color: const Color(0xFF1E1E3A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: onSelected,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.download_rounded, color: AppTheme.primary, size: 15),
          const SizedBox(width: 4),
          const Text('Save',
              style: TextStyle(
                  color: AppTheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
      itemBuilder: (_) => [
        _item(DownloadFormat.mp3, 'MP3', 'Universal compatibility',
            Colors.greenAccent),
        _item(DownloadFormat.m4a, 'M4A', 'High quality AAC', Colors.blueAccent),
        _item(
            DownloadFormat.flac, 'FLAC', 'Lossless audio', Colors.purpleAccent),
      ],
    );
  }

  PopupMenuItem<DownloadFormat> _item(
      DownloadFormat fmt, String label, String sub, Color color) {
    return PopupMenuItem(
      value: fmt,
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
              child: Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.bold))),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
          Text(sub,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
      ]),
    );
  }
}
