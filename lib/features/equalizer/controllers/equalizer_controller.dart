// lib/features/equalizer/controllers/equalizer_controller.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

const _channel = MethodChannel('com.resonance/equalizer');

class EqualizerPreset {
  final String name;
  final List<int> levels;
  const EqualizerPreset(this.name, this.levels);
}

const _presets = [
  EqualizerPreset('Flat', [0, 0, 0, 0, 0]),
  EqualizerPreset('Bass Boost', [800, 400, 0, 0, 0]),
  EqualizerPreset('Treble', [0, 0, 0, 400, 800]),
  EqualizerPreset('Rock', [500, 300, -100, 300, 500]),
  EqualizerPreset('Jazz', [300, 100, 200, 100, 300]),
  EqualizerPreset('Classical', [500, 300, -200, 200, 400]),
  EqualizerPreset('Vocal', [-200, 0, 300, 300, 100]),
  EqualizerPreset('Electronic', [600, 400, 0, 300, 500]),
];

class EqualizerController extends GetxController {
  RxBool enabled = true.obs;
  RxList<int> levels = <int>[0, 0, 0, 0, 0].obs;
  RxInt bassBoost = 0.obs;
  RxInt gain = 0.obs;
  RxInt virtualizer = 0.obs;
  RxInt selectedPreset = 0.obs;
  RxInt numBands = 5.obs;
  RxList<int> centerFreqs = <int>[].obs;
  RxInt minLevel = (-1500).obs;
  RxInt maxLevel = 1500.obs;

  // Track the last session ID we initialized with.
  // If the session ID changes (shouldn't normally happen with a shared player,
  // but can on some devices), we re-init.
  int? _lastSessionId;

  List<EqualizerPreset> get presets => _presets;

  bool get isInitialized => _lastSessionId != null;

  Future<void> init(int audioSessionId) async {
    // ── FIX: Guard on session ID, not a boolean ──────────────────────────
    // Old code: `if (_isInitialized) return;`
    // Problem: On the first song, _isInitialized was false → init ran → worked.
    // But the EQ screen showed "Play a song first" because numBands was 0
    // during the async gap. On the second song, _isInitialized was true → skipped.
    //
    // New behavior:
    // - If same session ID → skip (safe, no glitch)
    // - If different session ID → re-init (handles device edge cases)
    // - If first time → always init
    if (_lastSessionId == audioSessionId) return;

    try {
      await _channel.invokeMethod('init', {'sessionId': audioSessionId});

      final bands = (await _channel.invokeMethod<int>('getNumBands')) ?? 5;
      numBands.value = bands;

      final range =
          await _channel.invokeMethod<List<dynamic>>('getBandLevelRange');
      if (range != null && range.length == 2) {
        minLevel.value = (range[0] as int);
        maxLevel.value = (range[1] as int);
      }

      final freqs = <int>[];
      for (int i = 0; i < bands; i++) {
        final f = await _channel
                .invokeMethod<int>('getBandCenterFreq', {'band': i}) ??
            0;
        freqs.add(f);
      }
      centerFreqs.assignAll(freqs);

      final lvls = <int>[];
      for (int i = 0; i < bands; i++) {
        final l =
            await _channel.invokeMethod<int>('getBandLevel', {'band': i}) ?? 0;
        lvls.add(l);
      }
      levels.assignAll(lvls);

      // ── FIX: Mark initialized LAST, after all reactive vars are set ─────
      // Previously _isInitialized = true came BEFORE the data was loaded,
      // causing the EQ screen to render with stale/empty data on first open.
      _lastSessionId = audioSessionId;

      debugPrint('EQ initialized: $bands bands, '
          'range ${minLevel.value}..${maxLevel.value} mB, '
          'session: $audioSessionId');
    } catch (e) {
      // EQ not supported on this device — app keeps working without it.
      // Don't set _lastSessionId so we retry on next song.
      debugPrint('EQ init failed (non-fatal): $e');
    }
  }

  Future<void> setBandLevel(int band, int levelMillibels) async {
    if (!isInitialized) return;
    if (band < 0 || band >= levels.length) return;
    levels[band] = levelMillibels;
    try {
      await _channel.invokeMethod(
          'setBandLevel', {'band': band, 'level': levelMillibels});
    } catch (e) {
      debugPrint('setBandLevel error: $e');
    }
  }

  Future<void> setEnabled(bool value) async {
    if (!isInitialized) return;
    enabled.value = value;
    try {
      await _channel.invokeMethod('setEqEnabled', {'enabled': value});
    } catch (e) {
      debugPrint('setEnabled error: $e');
    }
  }

  Future<void> applyPreset(int index) async {
    if (index < 0 || index >= _presets.length) return;
    selectedPreset.value = index;
    final preset = _presets[index];
    for (int i = 0; i < numBands.value && i < preset.levels.length; i++) {
      await setBandLevel(i, preset.levels[i]);
    }
  }

  Future<void> setBassBoost(int strength) async {
    if (!isInitialized) return;
    bassBoost.value = strength.clamp(0, 1000);
    try {
      await _channel
          .invokeMethod('setBassBoost', {'strength': bassBoost.value});
    } catch (e) {
      debugPrint('setBassBoost error: $e');
    }
  }

  Future<void> setGain(int gainMillibels) async {
    if (!isInitialized) return;
    gain.value = gainMillibels.clamp(0, 1200);
    try {
      await _channel.invokeMethod('setGain', {'gain': gain.value});
    } catch (e) {
      debugPrint('setGain error: $e');
    }
  }

  Future<void> setVirtualizer(int strength) async {
    if (!isInitialized) return;
    virtualizer.value = strength.clamp(0, 1000);
    try {
      await _channel
          .invokeMethod('setVirtualizer', {'strength': virtualizer.value});
    } catch (e) {
      debugPrint('setVirtualizer error: $e');
    }
  }

  Future<void> release() async {
    if (!isInitialized) return;
    try {
      await _channel.invokeMethod('release');
      _lastSessionId = null;
    } catch (e) {
      debugPrint('EQ release error: $e');
    }
  }

  String freqLabel(int freqMilliHz) {
    final hz = freqMilliHz ~/ 1000;
    return hz >= 1000 ? '${(hz / 1000).toStringAsFixed(0)}k' : '$hz';
  }

  @override
  void onClose() {
    release();
    super.onClose();
  }
}
