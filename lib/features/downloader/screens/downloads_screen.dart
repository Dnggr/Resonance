import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/models/download_record.dart';
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
          Obx(() => svc.downloadHistory.isNotEmpty
              ? PopupMenuButton<String>(
                  color: const Color(0xFF1E1E3A),
                  icon: const Icon(Icons.more_vert_rounded,
                      color: Colors.white54),
                  onSelected: (val) {
                    if (val == 'clear') svc.clearHistory();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'clear',
                        child: Text('Clear all history',
                            style: TextStyle(color: Colors.redAccent))),
                  ],
                )
              : const SizedBox.shrink()),
        ],
      ),
      body: Obx(() {
        final active = svc.activeDownloads;
        final history = svc.downloadHistory;

        if (active.isEmpty && history.isEmpty) {
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
              _sectionHeader('Active', active.length, color: AppTheme.primary),
              const SizedBox(height: 8),
              ...active.map((t) => _ActiveTile(task: t, svc: svc)),
              const SizedBox(height: 20),
            ],
            if (history.isNotEmpty) ...[
              _sectionHeader('Downloaded', history.length,
                  color: Colors.greenAccent),
              const SizedBox(height: 8),
              ...history.map((r) => _HistoryTile(record: r, svc: svc)),
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

// ─── Active Download Tile ─────────────────────────────────────
class _ActiveTile extends StatelessWidget {
  final DownloadTask task;
  final DownloaderService svc;
  const _ActiveTile({required this.task, required this.svc});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final status = task.status.value;
      final isDone = status == DownloadStatus.done;
      final isError = status == DownloadStatus.error;
      final isPaused = status == DownloadStatus.paused;
      final isActive = status == DownloadStatus.downloading ||
          status == DownloadStatus.connecting;

      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isError
                ? AppTheme.accent.withOpacity(0.3)
                : isPaused
                    ? Colors.orangeAccent.withOpacity(0.3)
                    : isActive
                        ? AppTheme.primary.withOpacity(0.3)
                        : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(task.thumbnail,
                    width: 46,
                    height: 46,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        width: 46,
                        height: 46,
                        color: Colors.white10,
                        child: const Icon(Icons.music_note,
                            color: Colors.white30, size: 18))),
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
                      Text(task.author,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(task.formatLabel,
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
            if (isActive || isPaused) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: task.progress.value,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(
                    isPaused ? Colors.orangeAccent : AppTheme.primary),
                borderRadius: BorderRadius.circular(3),
                minHeight: 3,
              ),
              const SizedBox(height: 6),
            ],
            Row(children: [
              _statusIcon(status),
              const SizedBox(width: 6),
              Expanded(
                child: Text(task.statusLabel.value,
                    style: TextStyle(
                      color: isError
                          ? AppTheme.accent
                          : isPaused
                              ? Colors.orangeAccent
                              : Colors.white54,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (isActive && task.progress.value > 0)
                Text('${(task.progress.value * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              if (isActive)
                _actionBtn('Pause', Colors.white54, () => svc.pauseTask(task)),
              if (isPaused)
                _actionBtn(
                    'Resume', AppTheme.primary, () => svc.resumeTask(task),
                    borderColor: AppTheme.primary),
              if (isError)
                _actionBtn('Retry', AppTheme.accent, () => svc.retryTask(task),
                    borderColor: AppTheme.accent),
              if (isError || isPaused) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => svc.cancelTask(task),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white24, size: 18),
                ),
              ]
            ]),
          ]),
        ),
      );
    });
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap,
      {Color? borderColor}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: (borderColor ?? color).withOpacity(0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    );
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
      DownloadStatus.paused => const Icon(Icons.pause_circle_outline_rounded,
          color: Colors.orangeAccent, size: 13),
      DownloadStatus.done => const Icon(Icons.check_circle_rounded,
          color: Colors.greenAccent, size: 13),
      DownloadStatus.error =>
        const Icon(Icons.error_rounded, color: AppTheme.accent, size: 13),
      _ => const Icon(Icons.schedule_rounded, color: Colors.white24, size: 13),
    };
  }
}

// ─── History Tile (persisted) ─────────────────────────────────
class _HistoryTile extends StatelessWidget {
  final DownloadRecord record;
  final DownloaderService svc;
  const _HistoryTile({required this.record, required this.svc});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.15)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(record.thumbnail,
              width: 46,
              height: 46,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                  width: 46,
                  height: 46,
                  color: Colors.white10,
                  child: const Icon(Icons.music_note,
                      color: Colors.white30, size: 18))),
        ),
        title: Text(record.title,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(
            '${record.author} · ${record.format} · ${_fmtDate(record.downloadedAt)}',
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_rounded,
              color: Colors.greenAccent, size: 14),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _confirmDelete(context, svc, record),
            child: const Icon(Icons.delete_outline_rounded,
                color: Colors.white24, size: 20),
          ),
        ]),
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, DownloaderService svc, DownloadRecord record) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Delete download?',
            style: TextStyle(color: Colors.white)),
        content: Text('This will remove "${record.title}" from your device.',
            style: const TextStyle(color: Colors.white54)),
        actions: [
          TextButton(
              onPressed: () => Get.back(),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white38))),
          TextButton(
              onPressed: () {
                Get.back();
                svc.deleteHistoryRecord(record);
              },
              child: const Text('Delete',
                  style: TextStyle(color: AppTheme.accent))),
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
