import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/playlist_controller.dart';
import '../../player/controllers/player_controller.dart';
import '../../player/screens/now_playing_screen.dart';

class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final plCtrl = Get.find<PlaylistController>();
    final playerCtrl = Get.find<PlayerController>();
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Playlists',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: AppTheme.primary),
            onPressed: () => _showCreateDialog(context, plCtrl),
          ),
        ],
      ),
      body: Obx(() {
        if (plCtrl.playlists.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.queue_music_rounded,
                  size: 64, color: Colors.white12),
              const SizedBox(height: 12),
              const Text('No playlists yet',
                  style: TextStyle(color: Colors.white54, fontSize: 16)),
              const SizedBox(height: 6),
              const Text('Tap + to create one',
                  style: TextStyle(color: Colors.white30, fontSize: 13)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _showCreateDialog(context, plCtrl),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New Playlist'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white),
              ),
            ]),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: plCtrl.playlists.length,
          itemBuilder: (_, i) {
            final pl = plCtrl.playlists[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.playlist_play_rounded,
                      color: AppTheme.primary, size: 24),
                ),
                title: Text(pl.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
                subtitle: Text('${pl.songPaths.length} songs',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 12)),
                onTap: () async {
                  final allSongs = pl.songPaths.map((path) {
                    final name = path.split('/').last.replaceAll(
                        RegExp(r'\.(mp3|flac|m4a|aac|wav)$',
                            caseSensitive: false),
                        '');
                    final ext = path.split('.').last.toLowerCase();
                    return SongFile(path: path, name: name, ext: ext);
                  }).toList();

                  await playerCtrl.playFromPlaylist(allSongs, i, pl.name);
                  Get.to(() => const NowPlayingScreen(),
                      transition: Transition.downToUp);
                },
                trailing: PopupMenuButton<String>(
                  color: const Color(0xFF1E1E3A),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  icon: const Icon(Icons.more_vert_rounded,
                      color: Colors.white38),
                  onSelected: (val) {
                    if (val == 'rename')
                      _showRenameDialog(context, plCtrl, pl.id, pl.name);
                    if (val == 'delete') plCtrl.deletePlaylist(pl.id);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'rename',
                        child: Text('Rename',
                            style: TextStyle(color: Colors.white))),
                    const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete',
                            style: TextStyle(color: Colors.redAccent))),
                  ],
                ),
              ),
            );
          },
        );
      }),
    );
  }

  void _showCreateDialog(BuildContext context, PlaylistController plCtrl) {
    final tc = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title:
            const Text('New Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: tc,
          style: const TextStyle(color: Colors.white),
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: Colors.white30),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppTheme.primary)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Get.back(),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () {
              if (tc.text.trim().isNotEmpty) {
                plCtrl.createPlaylist(tc.text.trim());
                Get.back();
              }
            },
            child:
                const Text('Create', style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, PlaylistController plCtrl,
      String id, String current) {
    final tc = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Rename', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: tc,
          style: const TextStyle(color: Colors.white),
          autofocus: true,
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppTheme.primary)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Get.back(),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () {
              if (tc.text.trim().isNotEmpty) {
                plCtrl.renamePlaylist(id, tc.text.trim());
                Get.back();
              }
            },
            child:
                const Text('Save', style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }
}

class PlaylistDetailScreen extends StatelessWidget {
  final String playlistId;
  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context) {
    final plCtrl = Get.find<PlaylistController>();
    final playerCtrl = Get.find<PlayerController>();

    return Obx(() {
      final pl = plCtrl.playlists.firstWhereOrNull((p) => p.id == playlistId);
      if (pl == null) {
        Get.back();
        return const SizedBox.shrink();
      }
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.surface,
          title: Text(pl.name,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white),
            onPressed: () => Get.back(),
          ),
        ),
        body: pl.songPaths.isEmpty
            ? const Center(
                child: Text('No songs in this playlist',
                    style: TextStyle(color: Colors.white38)))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: pl.songPaths.length,
                itemBuilder: (_, i) {
                  final path = pl.songPaths[i];
                  final name = path.split('/').last.replaceAll(
                      RegExp(r'\.(mp3|flac|m4a|aac|wav)$',
                          caseSensitive: false),
                      '');
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: const Icon(Icons.music_note_rounded,
                        color: Colors.white30, size: 20),
                    title: Text(name,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    onTap: () async {
                      await playerCtrl.playSongByPath(path);
                      Get.to(() => const NowPlayingScreen(),
                          transition: Transition.downToUp);
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded,
                          color: Colors.white24, size: 20),
                      onPressed: () =>
                          plCtrl.removeSongFromPlaylist(playlistId, path),
                    ),
                  );
                },
              ),
      );
    });
  }
}
