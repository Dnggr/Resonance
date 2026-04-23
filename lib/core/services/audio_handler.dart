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
    // ─── FIX: Broadcast state on every playback event ────────────────────
    // This keeps the notification controls (play/pause/skip) in sync with
    // the actual player state. Without continuous broadcasting, the
    // notification can show stale controls (e.g. still showing "play" when
    // audio is already playing).
    player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e, StackTrace st) {
        debugPrint('AudioHandler playbackEventStream error: $e');
      },
    );

    // ─── Auto-advance to next track ──────────────────────────────────────
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        skipToNext();
      }
    });
  }

  // ─── Broadcast playback state to the notification / lock screen ──────────
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

  // ─── Play a file and update the notification metadata ────────────────────
  // IMPORTANT: mediaItem.add(item) MUST be called BEFORE setFilePath().
  // If you call setFilePath first, audio_service may broadcast a "loading"
  // state before the mediaItem is set, leaving the notification blank.
  Future<void> playFile(String path, MediaItem item) async {
    // 1. Set metadata first → notification shows correct title/art immediately
    mediaItem.add(item);

    // 2. Load and play audio
    await player.setFilePath(path);
    await player.play();
  }

// ─── Update metadata only (for when user edits song info mid-playback) ───
  // Call this after saving metadata changes so the lock screen updates
  // without needing to restart playback.
  @override
  Future<void> updateMediaItem(MediaItem item) async {
    mediaItem.add(item);

    // Re-broadcast state so Android redraws the notification with new info
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
    } catch (_) {
      // It's good practice to log errors here during development
    }
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
