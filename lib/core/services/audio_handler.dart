import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import '../../features/player/controllers/player_controller.dart';

class ResonanceAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer player;

  // Player is passed in — handler does not create its own AudioPlayer.
  // This is critical: the EQ session ID must come from the SAME player
  // instance that is used for playback. If the handler created its own
  // player, the session IDs would differ and EQ would affect nothing.
  ResonanceAudioHandler(this.player) {
    _init();
  }

  void _init() {
    player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e, StackTrace st) {
        debugPrint('AudioHandler stream error: $e');
      },
    );

    // When just_audio reaches end of track, trigger next
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) skipToNext();
    });
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = player.playing;

    // TRAP 5 FIX: use player.processingState as the map key,
    // not a hardcoded ProcessingState.idle
    final processingState = {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[player.processingState] ??
        AudioProcessingState.idle;

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
      processingState: processingState,
      playing: playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
    ));
  }

  // Earphone button routing:
  // Single tap = play/pause, double tap = next, triple tap = prev
  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.media:
        player.playing ? await pause() : await play();
        break;
      case MediaButton.next:
        await skipToNext();
        break;
      case MediaButton.previous:
        await skipToPrevious();
        break;
    }
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration pos) => player.seek(pos);

  @override
  Future<void> stop() async {
    await player.stop();
    return super.stop();
  }

  @override
  Future<void> skipToNext() async {
    // Typed find — no dynamic, no silent failures
    try {
      Get.find<PlayerController>().playNext();
    } catch (e) {
      debugPrint('skipToNext: PlayerController not found: $e');
    }
  }

  @override
  Future<void> skipToPrevious() async {
    try {
      Get.find<PlayerController>().playPrev();
    } catch (e) {
      debugPrint('skipToPrevious: PlayerController not found: $e');
    }
  }

  /// Call this whenever you want to load + play a new file.
  /// Updates the lock screen / notification metadata.
  Future<void> playFile(String path, MediaItem item) async {
    mediaItem.add(item);
    await player.setFilePath(path);
    await player.play();
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
    return super.onTaskRemoved();
  }
}
