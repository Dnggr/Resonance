// Singleton service to get / set user-editable metadata for any song path.

import 'package:get/get.dart';
import 'package:hive/hive.dart';
import '../models/song_metadata.dart';

class MetadataService extends GetxController {
  late Box<SongMetadata> _box;

  @override
  void onInit() {
    super.onInit();
    _box = Hive.box<SongMetadata>('song_metadata');
  }

  SongMetadata? get(String filePath) => _box.get(filePath);

  Future<void> save(SongMetadata meta) async {
    await _box.put(meta.filePath, meta);
  }

  /// Returns the display title (custom first, then filename stem).
  String displayTitle(String filePath, String fallbackName) {
    return _box.get(filePath)?.customTitle?.trim().isNotEmpty == true
        ? _box.get(filePath)!.customTitle!
        : fallbackName;
  }

  String displayArtist(String filePath) {
    return _box.get(filePath)?.customArtist?.trim().isNotEmpty == true
        ? _box.get(filePath)!.customArtist!
        : 'Unknown Artist';
  }

  String displayAlbum(String filePath) {
    return _box.get(filePath)?.customAlbum?.trim().isNotEmpty == true
        ? _box.get(filePath)!.customAlbum!
        : 'Unknown Album';
  }

  String? artImagePath(String filePath) => _box.get(filePath)?.artImagePath;
}
