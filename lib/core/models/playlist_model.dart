import 'package:hive/hive.dart';

part 'playlist_model.g.dart';

@HiveType(typeId: 0)
class PlaylistModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  List<String> songPaths;

  @HiveField(3)
  DateTime createdAt;

  PlaylistModel({
    required this.id,
    required this.name,
    required this.songPaths,
    required this.createdAt,
  });
}
