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

  // Guard: don't double-init AudioEffect objects
  bool _isInitialized = false;

  List<EqualizerPreset> get presets => _presets;

  Future<void> init(int audioSessionId) async {
    // Already initialized — AudioEffect is tied to AudioPlayer session
    // which doesn't change between songs. Re-initializing would cause
    // a ~200ms audio glitch and waste resources.
    if (_isInitialized) return;

    try {
      await _channel.invokeMethod('init', {'sessionId': audioSessionId});

      numBands.value = (await _channel.invokeMethod<int>('getNumBands')) ?? 5;

      final range =
          await _channel.invokeMethod<List<dynamic>>('getBandLevelRange');
      if (range != null && range.length == 2) {
        minLevel.value = (range[0] as int);
        maxLevel.value = (range[1] as int);
      }

      final freqs = <int>[];
      for (int i = 0; i < numBands.value; i++) {
        final f = await _channel
                .invokeMethod<int>('getBandCenterFreq', {'band': i}) ??
            0;
        freqs.add(f);
      }
      centerFreqs.assignAll(freqs);

      final lvls = <int>[];
      for (int i = 0; i < numBands.value; i++) {
        final l =
            await _channel.invokeMethod<int>('getBandLevel', {'band': i}) ?? 0;
        lvls.add(l);
      }
      levels.assignAll(lvls);

      _isInitialized = true;
      debugPrint('EQ initialized: ${numBands.value} bands, '
          'range ${minLevel.value}..${maxLevel.value} mB');
    } catch (e) {
      // EQ not supported on this device — app keeps working without it
      debugPrint('EQ init failed (non-fatal): $e');
    }
  }

  Future<void> setBandLevel(int band, int levelMillibels) async {
    if (!_isInitialized) return;
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
    if (!_isInitialized) return;
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
    if (!_isInitialized) return;
    bassBoost.value = strength.clamp(0, 1000);
    try {
      await _channel
          .invokeMethod('setBassBoost', {'strength': bassBoost.value});
    } catch (e) {
      debugPrint('setBassBoost error: $e');
    }
  }

  Future<void> setGain(int gainMillibels) async {
    if (!_isInitialized) return;
    gain.value = gainMillibels.clamp(0, 1200);
    try {
      await _channel.invokeMethod('setGain', {'gain': gain.value});
    } catch (e) {
      debugPrint('setGain error: $e');
    }
  }

  Future<void> setVirtualizer(int strength) async {
    if (!_isInitialized) return;
    virtualizer.value = strength.clamp(0, 1000);
    try {
      await _channel
          .invokeMethod('setVirtualizer', {'strength': virtualizer.value});
    } catch (e) {
      debugPrint('setVirtualizer error: $e');
    }
  }

  Future<void> release() async {
    if (!_isInitialized) return;
    try {
      await _channel.invokeMethod('release');
      _isInitialized = false;
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
