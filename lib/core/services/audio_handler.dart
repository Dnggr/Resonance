import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';

/// Call this once in main() before runApp
Future<ResonanceAudioHandler> initAudioService() async {
  return await AudioService.init(
    builder: () => ResonanceAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.resonance.audio',
      androidNotificationChannelName: 'Resonance Player',
      androidNotificationOngoing: true,
      androidShowNotificationBadge: true,
      notificationColor: Color(0xFF6C63FF),
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );
}

class ResonanceAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer player = AudioPlayer();

  ResonanceAudioHandler() {
    _init();
  }

  Future<void> _init() async {
    // Pipe just_audio state → audio_service state
    player.playbackEventStream.listen(_broadcastState);
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) skipToNext();
    });
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[player.processingState]!,
      playing: playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
    ));
  }

  // ── Earphone button routing ──────────────────────────────
  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.media:
        playing ? await pause() : await play();
        break;
      case MediaButton.next:
        await skipToNext();
        break;
      case MediaButton.previous:
        await skipToPrevious();
        break;
    }
  }

  // ── Playback commands ────────────────────────────────────
  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> stop() {
    player.stop();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() async {
    // Delegate to PlayerController via GetX
    try {
      Get.find<dynamic>().playNext();
    } catch (_) {}
  }

  @override
  Future<void> skipToPrevious() async {
    try {
      Get.find<dynamic>().playPrev();
    } catch (_) {}
  }

  /// Call this whenever you want to load + play a new file
  Future<void> playFile(String path, MediaItem item) async {
    mediaItem.add(item);
    await player.setFilePath(path);
    await player.play();
  }

  bool get playing => player.playing;

  @override
  Future<void> onTaskRemoved() async {
    await stop();
    return super.onTaskRemoved();
  }
}
