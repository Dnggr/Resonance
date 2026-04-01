import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/theme/app_theme.dart';
import '../services/downloader_service.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = Get.find<DownloaderService>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Downloads',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        actions: [
          Obx(() => svc.completedDownloads.isNotEmpty
              ? TextButton(
                  onPressed: svc.clearCompleted,
                  child: const Text('Clear done',
                      style: TextStyle(color: AppTheme.primary, fontSize: 13)),
                )
              : const SizedBox.shrink()),
        ],
      ),
      body: Obx(() {
        final active = svc.activeDownloads;
        final done = svc.completedDownloads;

        if (active.isEmpty && done.isEmpty) {
          return const Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.download_rounded, size: 64, color: Colors.white12),
              SizedBox(height: 12),
              Text('No downloads yet',
                  style: TextStyle(color: Colors.white30, fontSize: 15)),
              SizedBox(height: 6),
              Text('Search for music and tap Save',
                  style: TextStyle(color: Colors.white24, fontSize: 13)),
            ]),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (active.isNotEmpty) ...[
              _sectionHeader('Downloading', active.length,
                  color: AppTheme.primary),
              const SizedBox(height: 8),
              ...active.map((t) => _DownloadTile(task: t, svc: svc)),
              const SizedBox(height: 20),
            ],
            if (done.isNotEmpty) ...[
              _sectionHeader('Completed', done.length,
                  color: Colors.greenAccent),
              const SizedBox(height: 8),
              ...done.map((t) => _DownloadTile(task: t, svc: svc)),
            ],
          ],
        );
      }),
    );
  }

  Widget _sectionHeader(String title, int count, {required Color color}) {
    return Row(children: [
      Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10)),
        child: Text('$count',
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    ]);
  }
}

// ─── Download Tile ────────────────────────────────────────────
class _DownloadTile extends StatelessWidget {
  final DownloadTask task;
  final DownloaderService svc;
  const _DownloadTile({required this.task, required this.svc});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final status = task.status.value;
      final isDone = status == DownloadStatus.done;
      final isError = status == DownloadStatus.error;
      final isActive = status == DownloadStatus.downloading ||
          status == DownloadStatus.connecting ||
          status == DownloadStatus.converting;

      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDone
                ? Colors.greenAccent.withOpacity(0.25)
                : isError
                    ? AppTheme.accent.withOpacity(0.25)
                    : isActive
                        ? AppTheme.primary.withOpacity(0.25)
                        : Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    task.thumbnail,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        width: 48,
                        height: 48,
                        color: Colors.white10,
                        child: const Icon(Icons.music_note,
                            color: Colors.white30, size: 20)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(task.author,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Format badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(task.formatLabel,
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              ]),

              const SizedBox(height: 10),

              // ── Progress bar ──────────────────────────
              if (isActive || isDone) ...[
                LinearProgressIndicator(
                  value: task.progress.value,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      isDone ? Colors.greenAccent : AppTheme.primary),
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 3,
                ),
                const SizedBox(height: 6),
              ],

              // ── Status Row ────────────────────────────
              Row(children: [
                _statusIcon(status),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    task.statusLabel.value,
                    style: TextStyle(
                      color: isDone
                          ? Colors.greenAccent
                          : isError
                              ? AppTheme.accent
                              : Colors.white54,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isActive && task.progress.value > 0)
                  Text(
                    '${(task.progress.value * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                if (isError)
                  GestureDetector(
                    onTap: () => svc.retryTask(task),
                    child: Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: AppTheme.accent.withOpacity(0.3)),
                      ),
                      child: const Text('Retry',
                          style: TextStyle(
                              color: AppTheme.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
              ]),
            ],
          ),
        ),
      );
    });
  }

  Widget _statusIcon(DownloadStatus s) {
    return switch (s) {
      DownloadStatus.connecting => const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
              strokeWidth: 1.5, color: Colors.white38)),
      DownloadStatus.downloading => const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
              strokeWidth: 1.5, color: AppTheme.primary)),
      DownloadStatus.converting => const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
              strokeWidth: 1.5, color: Colors.purpleAccent)),
      DownloadStatus.done => const Icon(Icons.check_circle_rounded,
          color: Colors.greenAccent, size: 13),
      DownloadStatus.error =>
        const Icon(Icons.error_rounded, color: AppTheme.accent, size: 13),
      _ => const Icon(Icons.schedule_rounded, color: Colors.white24, size: 13),
    };
  }
}
