import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/theme/app_theme.dart';
import '../services/downloader_service.dart';

class DownloadQueueTile extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onRemove;

  const DownloadQueueTile({
    super.key,
    required this.task,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final status = task.status.value;
      final progress = task.progress.value;

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _borderColor(status), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _statusIcon(status),
              const SizedBox(width: 10),
              Expanded(
                child: Text(task.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (status == DownloadStatus.done ||
                  status == DownloadStatus.error)
                GestureDetector(
                  onTap: onRemove,
                  child:
                      const Icon(Icons.close, color: Colors.white38, size: 18),
                ),
            ]),
            if (status == DownloadStatus.downloading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white10,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 4),
              Text('${(progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ],
            if (status == DownloadStatus.error &&
                task.errorMessage != null) ...[
              const SizedBox(height: 4),
              Text(task.errorMessage!,
                  style: const TextStyle(color: AppTheme.accent, fontSize: 10)),
            ],
            if (status == DownloadStatus.done && task.filePath != null) ...[
              const SizedBox(height: 4),
              Text('Saved ✓',
                  style:
                      const TextStyle(color: Colors.greenAccent, fontSize: 10)),
            ],
          ],
        ),
      );
    });
  }

  Color _borderColor(DownloadStatus s) {
    return switch (s) {
      DownloadStatus.downloading => AppTheme.primary.withOpacity(0.5),
      DownloadStatus.done => Colors.greenAccent.withOpacity(0.4),
      DownloadStatus.error => AppTheme.accent.withOpacity(0.4),
      _ => Colors.white10,
    };
  }

  Widget _statusIcon(DownloadStatus s) {
    return switch (s) {
      DownloadStatus.downloading => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppTheme.primary)),
      DownloadStatus.done =>
        const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
      DownloadStatus.error =>
        const Icon(Icons.error_outline, color: AppTheme.accent, size: 16),
      _ => const Icon(Icons.hourglass_empty, color: Colors.white38, size: 16),
    };
  }
}
