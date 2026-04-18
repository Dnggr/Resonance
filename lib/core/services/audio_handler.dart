// lib/core/services/audio_handler.dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import '../../features/player/controllers/player_controller.dart';

class ResonanceAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer player;

  ResonanceAudioHandler(this.player) {
    _init();
  }

  void _init() {
    // ── FIX: Use a single combined stream for all state broadcasts ─────────
    // Previously two listeners (playbackEventStream + playingStream) both
    // called _broadcastState, causing double-fire on every play/pause.
    // Double-fire is harmless BUT it can confuse the notification system
    // on some Android versions, causing the controls to flicker or not update.
    //
    // just_audio's playbackEventStream fires on EVERY state change including
    // play/pause/seek/buffer — so it's the only listener we need.
    player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e, StackTrace st) {
        debugPrint('AudioHandler playbackEventStream error: $e');
      },
    );

    // Track completion to auto-advance
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        skipToNext();
      }
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

  /// Set the song metadata on the notification + lock screen,
  /// then load and play the file.
  ///
  /// ── FIX: mediaItem is set BEFORE setFilePath() ─────────────────────────
  /// Android reads mediaItem to populate the notification. If we set it after
  /// loading starts, there's a window where the notification shows blank/stale
  /// info. Setting it first ensures the notification always has correct data.
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
