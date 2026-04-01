import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../../core/theme/app_theme.dart';
import '../services/downloader_service.dart';

class SearchResultCard extends StatelessWidget {
  final Video video;
  final Function(DownloadFormat) onDownload;

  const SearchResultCard({
    super.key,
    required this.video,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(10),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            video.thumbnails.lowResUrl,
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 64,
              height: 64,
              color: Colors.white10,
              child: const Icon(Icons.music_note, color: Colors.white30),
            ),
          ),
        ),
        title: Text(
          video.title,
          style: const TextStyle(
              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${video.author} • ${_formatDuration(video.duration)}',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        trailing: _DownloadButton(onDownload: onDownload),
      ),
    );
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '--:--';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }
}

class _DownloadButton extends StatelessWidget {
  final Function(DownloadFormat) onDownload;
  const _DownloadButton({required this.onDownload});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<DownloadFormat>(
      icon: const Icon(Icons.download_rounded, color: AppTheme.primary),
      color: const Color(0xFF1E1E3A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: onDownload,
      itemBuilder: (_) => [
        _menuItem(DownloadFormat.mp3, Icons.audiotrack, 'MP3 (Audio)',
            Colors.greenAccent),
        _menuItem(DownloadFormat.mp4, Icons.videocam, 'MP4 (Video)',
            Colors.blueAccent),
      ],
    );
  }

  PopupMenuItem<DownloadFormat> _menuItem(
      DownloadFormat format, IconData icon, String label, Color color) {
    return PopupMenuItem(
      value: format,
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: Colors.white)),
      ]),
    );
  }
}
