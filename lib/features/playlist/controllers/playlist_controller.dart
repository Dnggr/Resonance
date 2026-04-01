import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/playlist_model.dart';

// Add uuid to pubspec.yaml: uuid: ^4.4.0
class PlaylistController extends GetxController {
  late Box<PlaylistModel> _box;
  RxList<PlaylistModel> playlists = <PlaylistModel>[].obs;

  @override
  void onInit() {
    super.onInit();
    _box = Hive.box<PlaylistModel>('playlists');
    playlists.assignAll(_box.values.toList());
  }

  void createPlaylist(String name) {
    final pl = PlaylistModel(
      id: const Uuid().v4(),
      name: name,
      songPaths: [],
      createdAt: DateTime.now(),
    );
    _box.put(pl.id, pl);
    playlists.assignAll(_box.values.toList());
  }

  void addSongToPlaylist(String playlistId, String songPath) {
    final pl = _box.get(playlistId);
    if (pl == null) return;
    if (!pl.songPaths.contains(songPath)) {
      pl.songPaths.add(songPath);
      pl.save();
      playlists.assignAll(_box.values.toList());
    }
  }

  void removeSongFromPlaylist(String playlistId, String songPath) {
    final pl = _box.get(playlistId);
    if (pl == null) return;
    pl.songPaths.remove(songPath);
    pl.save();
    playlists.assignAll(_box.values.toList());
  }

  void deletePlaylist(String playlistId) {
    _box.delete(playlistId);
    playlists.assignAll(_box.values.toList());
  }

  void renamePlaylist(String playlistId, String newName) {
    final pl = _box.get(playlistId);
    if (pl == null) return;
    pl.name = newName;
    pl.save();
    playlists.assignAll(_box.values.toList());
  }
}
