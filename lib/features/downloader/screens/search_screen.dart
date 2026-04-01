import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
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

  // Preview player
  final AudioPlayer _preview = AudioPlayer();
  String? _previewingId;
  bool _previewLoading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _preview.dispose();
    super.dispose();
  }

  Future<void> _togglePreview(String videoId) async {
    if (_previewingId == videoId && _preview.playing) {
      await _preview.pause();
      setState(() => _previewingId = null);
      return;
    }
    setState(() {
      _previewLoading = true;
      _previewingId = videoId;
    });
    try {
      final url = await _svc.getPreviewUrl(videoId);
      if (url == null) throw Exception('No stream');
      await _preview.setUrl(url);
      await _preview.play();
    } catch (_) {
      setState(() => _previewingId = null);
    } finally {
      setState(() => _previewLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Search',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5)),
              const Text('Preview & download audio',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
            ]),
          ),
          Obx(() {
            final active = _svc.activeDownloads.length;
            final total = active + _svc.completedDownloads.length;
            return GestureDetector(
              onTap: () => Get.to(() => const DownloadsScreen()),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: active > 0
                          ? AppTheme.primary.withOpacity(0.5)
                          : Colors.white10),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (active > 0)
                    const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.primary))
                  else
                    const Icon(Icons.download_done_rounded,
                        color: Colors.white54, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    active > 0
                        ? '$active active'
                        : total > 0
                            ? '$total done'
                            : 'Downloads',
                    style: TextStyle(
                        color: active > 0 ? AppTheme.primary : Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ]),
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
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.primary)))
                    : _ctrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                color: Colors.white38, size: 18),
                            onPressed: () {
                              _ctrl.clear();
                              _svc.searchResults.clear();
                              setState(() {});
                            })
                        : const SizedBox.shrink()),
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: AppTheme.primary, width: 1.5)),
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
                  borderRadius: BorderRadius.circular(14)),
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
          itemBuilder: (_, i) {
            final video = _svc.searchResults[i];
            final isPreviewingThis = _previewingId == video.id.value;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isPreviewingThis
                      ? AppTheme.primary.withOpacity(0.5)
                      : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    // Thumbnail with preview overlay
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: video.thumbnails.lowResUrl,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                                width: 56, height: 56, color: Colors.white10),
                            errorWidget: (_, __, ___) => Container(
                                width: 56,
                                height: 56,
                                color: Colors.white10,
                                child: const Icon(Icons.music_note,
                                    color: Colors.white30, size: 24)),
                          ),
                        ),
                        // Preview button overlay
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: () => _togglePreview(video.id.value),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: isPreviewingThis
                                    ? Colors.black45
                                    : Colors.black26,
                              ),
                              child: _previewLoading && isPreviewingThis
                                  ? const Center(
                                      child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white)))
                                  : Icon(
                                      isPreviewingThis && _preview.playing
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 24),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
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
                            Text('${video.author} · ${_dur(video.duration)}',
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 11)),
                          ]),
                    ),
                    const SizedBox(width: 8),
                    _FormatPicker(
                        onSelected: (fmt) => _svc.queueDownload(video, fmt)),
                  ],
                ),
              ),
            );
          },
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
        _item(DownloadFormat.mp3, 'MP3', 'Universal', Colors.greenAccent),
        _item(DownloadFormat.m4a, 'M4A', 'High quality AAC', Colors.blueAccent),
        _item(DownloadFormat.flac, 'FLAC', 'Lossless', Colors.purpleAccent),
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
              borderRadius: BorderRadius.circular(8)),
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
