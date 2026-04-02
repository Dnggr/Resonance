import 'package:hive/hive.dart';

part 'download_record.g.dart';

@HiveType(typeId: 1)
class DownloadRecord extends HiveObject {
  @HiveField(0)
  String videoId;

  @HiveField(1)
  String title;

  @HiveField(2)
  String author;

  @HiveField(3)
  String thumbnail;

  @HiveField(4)
  String filePath;

  @HiveField(5)
  String format;

  @HiveField(6)
  DateTime downloadedAt;

  DownloadRecord({
    required this.videoId,
    required this.title,
    required this.author,
    required this.thumbnail,
    required this.filePath,
    required this.format,
    required this.downloadedAt,
  });
}
