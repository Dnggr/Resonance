import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/theme/app_theme.dart';
import '../services/downloader_service.dart';
import '../widgets/search_result_card.dart';
import '../widgets/download_queue_tile.dart';

class DownloaderScreen extends StatefulWidget {
  const DownloaderScreen({super.key});

  @override
  State<DownloaderScreen> createState() => _DownloaderScreenState();
}

class _DownloaderScreenState extends State<DownloaderScreen> {
  final DownloaderService _svc = Get.put(DownloaderService());
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
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
            // ── Header ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Download',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold)),
                  Text('Search & save music to your device',
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Search Bar ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Song name, artist...',
                      hintStyle: const TextStyle(color: Colors.white30),
                      prefixIcon:
                          const Icon(Icons.search, color: Colors.white38),
                      filled: true,
                      fillColor: AppTheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onSubmitted: _svc.searchMusic,
                  ),
                ),
                const SizedBox(width: 10),
                Obx(() => _svc.searchStatus.value == DownloadStatus.searching
                    ? const SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.primary)))
                    : ElevatedButton(
                        onPressed: () => _svc.searchMusic(_searchCtrl.text),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          minimumSize: const Size(48, 48),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Icon(Icons.search, color: Colors.white),
                      )),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Download Queue ───────────────────────────────
            Obx(() {
              if (_svc.downloadQueue.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Queue (${_svc.downloadQueue.length})',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        GestureDetector(
                          onTap: _svc.clearCompleted,
                          child: const Text('Clear done',
                              style: TextStyle(
                                  color: AppTheme.primary, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  ...(_svc.downloadQueue.map((task) => DownloadQueueTile(
                        task: task,
                        onRemove: () => _svc.removeFromQueue(task),
                      ))),
                  const Divider(color: Colors.white10, height: 24),
                ],
              );
            }),

            // ── Search Results ───────────────────────────────
            Expanded(
              child: Obx(() {
                if (_svc.searchStatus.value == DownloadStatus.error) {
                  return Center(
                    child: Text(_svc.searchError.value,
                        style: const TextStyle(color: AppTheme.accent)),
                  );
                }
                if (_svc.searchResults.isEmpty &&
                    _svc.searchStatus.value == DownloadStatus.idle) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.queue_music,
                            size: 64, color: Colors.white12),
                        SizedBox(height: 12),
                        Text('Search for music above',
                            style: TextStyle(color: Colors.white30)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: _svc.searchResults.length,
                  padding: const EdgeInsets.only(bottom: 16),
                  itemBuilder: (_, i) {
                    final video = _svc.searchResults[i];
                    return SearchResultCard(
                      video: video,
                      onDownload: (fmt) => _svc.downloadTrack(video, fmt),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
