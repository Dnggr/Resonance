// import 'package:audio_service/audio_service.dart';
// import 'package:just_audio/just_audio.dart';
// // import 'package:flutter/material.dart';
// import 'package:get/get.dart';

// class ResonanceAudioHandler extends BaseAudioHandler
//     with QueueHandler, SeekHandler {
//   final AudioPlayer player = AudioPlayer();

//   ResonanceAudioHandler() {
//     _init();
//   }

//   Future<void> _init() async {
//     player.playbackEventStream.listen(_broadcastState);
//     player.processingStateStream.listen((state) {
//       if (state == ProcessingState.completed) skipToNext();
//     });
//   }

//   void _broadcastState(PlaybackEvent event) {
//     final playing = player.playing;
//     playbackState.add(playbackState.value.copyWith(
//       controls: [
//         MediaControl.skipToPrevious,
//         playing ? MediaControl.pause : MediaControl.play,
//         MediaControl.skipToNext,
//       ],
//       systemActions: const {
//         MediaAction.seek,
//         MediaAction.skipToNext,
//         MediaAction.skipToPrevious,
//       },
//       androidCompactActionIndices: const [0, 1, 2],
//       processingState: const {
//         ProcessingState.idle: AudioProcessingState.idle,
//         ProcessingState.loading: AudioProcessingState.loading,
//         ProcessingState.buffering: AudioProcessingState.buffering,
//         ProcessingState.ready: AudioProcessingState.ready,
//         ProcessingState.completed: AudioProcessingState.completed,
//       }[ProcessingState.idle]!,
//       playing: playing,
//       updatePosition: player.position,
//       bufferedPosition: player.bufferedPosition,
//       speed: player.speed,
//     ));
//   }

//   @override
//   Future<void> click([MediaButton button = MediaButton.media]) async {
//     switch (button) {
//       case MediaButton.media:
//         player.playing ? await pause() : await play();
//         break;
//       case MediaButton.next:
//         await skipToNext();
//         break;
//       case MediaButton.previous:
//         await skipToPrevious();
//         break;
//     }
//   }

//   @override
//   Future<void> play() => player.play();
//   @override
//   Future<void> pause() => player.pause();
//   @override
//   Future<void> seek(Duration pos) => player.seek(pos);

//   @override
//   Future<void> stop() async {
//     await player.stop();
//     return super.stop();
//   }

//   @override
//   Future<void> skipToNext() async {
//     try {
//       // Calls PlayerController.playNext() via GetX
//       Get.find<dynamic>().playNext();
//     } catch (_) {}
//   }

//   @override
//   Future<void> skipToPrevious() async {
//     try {
//       Get.find<dynamic>().playPrev();
//     } catch (_) {}
//   }

//   Future<void> playFile(String path, MediaItem item) async {
//     mediaItem.add(item);
//     await player.setFilePath(path);
//     await player.play();
//   }

//   bool get playing => player.playing;

//   @override
//   Future<void> onTaskRemoved() async {
//     await stop();
//     return super.onTaskRemoved();
//   }
// }
