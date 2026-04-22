// lib/core/models/song_metadata.dart
//
// Persists user-editable metadata (title, artist, album, custom art path)
// keyed by the song's file path. Uses Hive for persistence.

import 'package:hive/hive.dart';

part 'song_metadata.g.dart';

@HiveType(typeId: 2)
class SongMetadata extends HiveObject {
  @HiveField(0)
  String filePath;

  @HiveField(1)
  String? customTitle;

  @HiveField(2)
  String? customArtist;

  @HiveField(3)
  String? customAlbum;

  /// Path to a user-picked PNG/JPEG image stored in app documents directory.
  @HiveField(4)
  String? artImagePath;

  SongMetadata({
    required this.filePath,
    this.customTitle,
    this.customArtist,
    this.customAlbum,
    this.artImagePath,
  });
}
