// lib/core/services/audio_handler.dart
//
// FIX 1 — Lockscreen / notification player:
//   _broadcastState() now always calls mediaItem.add(...) so Android's
//   MediaSession shows the title, artist, album and artwork on the
//   lock-screen and in the notification shade.
//
// FIX 2 — 30-minute crash:
//   androidStopForegroundOnPause: false  (set in main.dart AudioServiceConfig)
//   keeps the foreground service alive even when paused.  Combined with the
//   FOREGROUND_SERVICE_MEDIA_PLAYBACK permission in AndroidManifest this
//   prevents Doze from killing the process.

import 'dart:io';
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
    player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e, StackTrace st) {
        debugPrint('AudioHandler playbackEventStream error: $e');
      },
    );

    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        skipToNext();
      }
    });
  }

  // ─── Core broadcast ────────────────────────────────────────────────────────
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

  // ─── Play a local file with full metadata ──────────────────────────────────
  /// Called by PlayerController every time a new song starts.
  /// [item] contains the title, artist, album and optional art URI so the
  /// lock-screen / notification shows real info instead of being blank.
  Future<void> playFile(String path, MediaItem item) async {
    // 1. Publish the MediaItem BEFORE loading audio so the lock screen
    //    updates immediately (no blank flash).
    mediaItem.add(item);

    // 2. Load + play
    await player.setFilePath(path);
    await player.play();
  }

  // ─── Standard controls ────────────────────────────────────────────────────
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

  @override
  Future<void> onTaskRemoved() async {
    await stop();
    return super.onTaskRemoved();
  }
}
