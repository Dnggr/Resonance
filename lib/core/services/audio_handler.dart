// lib/core/services/audio_handler.dart
//
// FIX LOG:
//  [BUG-1] CRASH — Double track-complete handler removed.
//  Previously BOTH audio_handler.dart (here) AND player_controller.dart
//  listened to processingStateStream and called skipToNext()/_onTrackComplete()
//  simultaneously on every natural track end. This caused a race: either two
//  songs were skipped, or the same song played twice.
//
//  FIX: audio_handler.dart NO LONGER listens to processingStateStream.
//  player_controller.dart is the single source of truth for track-complete
//  logic (_onTrackComplete handles loop/shuffle/advance).
//  skipToNext() / skipToPrevious() here just delegate to PlayerController
//  so notification buttons still work.
//
//  [BUG-2] CRASH — _eqInitSub cancel-inside-callback removed from handler.
//  The old handler had an `await _eqInitSub?.cancel()` call inside a
//  stream.listen() callback, which can throw "Bad state: Stream already
//  cancelled" on some Dart versions. That logic now lives exclusively in
//  player_controller.dart with a safe guard pattern.

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
    // Broadcast state on every playback event — keeps notification controls
    // (play/pause/skip) in sync with the actual player state.
    player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e, StackTrace st) {
        debugPrint('AudioHandler playbackEventStream error: $e');
      },
    );

    // ─── FIX BUG-1: NO processingStateStream listener here. ─────────────
    // Track-complete auto-advance is handled ONLY in player_controller.dart
    // (_onTrackComplete). Having it in both places caused double-advance /
    // same-song-repeated races. Removed.
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

  // IMPORTANT: mediaItem.add(item) MUST be called BEFORE setFilePath().
  // If you call setFilePath first, audio_service may broadcast a "loading"
  // state before the mediaItem is set, leaving the notification blank.
  Future<void> playFile(String path, MediaItem item) async {
    mediaItem.add(item);
    await player.setFilePath(path);
    await player.play();
  }

  // Call this after saving metadata changes so the lock screen updates
  // without needing to restart playback.
  @override
  Future<void> updateMediaItem(MediaItem item) async {
    mediaItem.add(item);
    try {
      _broadcastState(PlaybackEvent(
        processingState: player.processingState,
        updateTime: DateTime.now(),
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        icyMetadata: null,
        duration: player.duration,
        currentIndex: null,
      ));
    } catch (_) {}
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

  @override
  Future<void> onTaskRemoved() async {
    await stop();
    return super.onTaskRemoved();
  }
}
