// lib/core/services/audio_handler.dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import '../../features/player/controllers/player_controller.dart';

class ResonanceAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer player;

  // Player is passed in — NOT created here.
  // Handler and PlayerController share the exact same instance
  // so EQ audio session IDs always match.
  ResonanceAudioHandler(this.player) {
    _init();
  }

  void _init() {
    // ── FIX: Listen to playback events and broadcast them ─────────────────
    // This is what drives the lock-screen / notification controls.
    player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e, StackTrace st) {
        debugPrint('AudioHandler stream error: $e');
      },
    );

    // ── FIX: Also listen to playing state changes separately ──────────────
    // playbackEventStream doesn't always fire on play/pause toggles alone.
    player.playingStream.listen((_) {
      _broadcastState(
        PlaybackEvent(
          processingState: player.processingState,
          updatePosition: player.position,
          bufferedPosition: player.bufferedPosition,
        ),
      );
    });

    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) skipToNext();
    });
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = player.playing;

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
        MediaAction.seekForward,
        MediaAction.seekBackward,
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
  // Single tap  → play/pause
  // Double tap  → next
  // Triple tap  → prev
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

  /// Load a file and update the lock screen / notification metadata.
  /// This is the primary entry point for playing a song WITH notification support.
  Future<void> playFile(String path, MediaItem item) async {
    // ── FIX: Update mediaItem BEFORE setting the file path ────────────────
    // audio_service needs this to display song info on the lock screen.
    // Setting it after setFilePath() causes a race where the notification
    // shows blank or stale info on the first play.
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
