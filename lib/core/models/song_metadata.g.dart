// lib/core/models/song_metadata.g.dart
// HAND-WRITTEN (equivalent to what hive_generator would produce)

part of 'song_metadata.dart';

class SongMetadataAdapter extends TypeAdapter<SongMetadata> {
  @override
  final int typeId = 2;

  @override
  SongMetadata read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SongMetadata(
      filePath: fields[0] as String,
      customTitle: fields[1] as String?,
      customArtist: fields[2] as String?,
      customAlbum: fields[3] as String?,
      artImagePath: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SongMetadata obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.filePath)
      ..writeByte(1)
      ..write(obj.customTitle)
      ..writeByte(2)
      ..write(obj.customArtist)
      ..writeByte(3)
      ..write(obj.customAlbum)
      ..writeByte(4)
      ..write(obj.artImagePath);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongMetadataAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
