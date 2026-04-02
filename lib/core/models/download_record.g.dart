// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_record.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DownloadRecordAdapter extends TypeAdapter<DownloadRecord> {
  @override
  final int typeId = 1;

  @override
  DownloadRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DownloadRecord(
      videoId: fields[0] as String,
      title: fields[1] as String,
      author: fields[2] as String,
      thumbnail: fields[3] as String,
      filePath: fields[4] as String,
      format: fields[5] as String,
      downloadedAt: fields[6] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, DownloadRecord obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.videoId)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.author)
      ..writeByte(3)
      ..write(obj.thumbnail)
      ..writeByte(4)
      ..write(obj.filePath)
      ..writeByte(5)
      ..write(obj.format)
      ..writeByte(6)
      ..write(obj.downloadedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
