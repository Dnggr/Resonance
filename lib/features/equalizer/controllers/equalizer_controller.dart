import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flutter/foundation.dart';

const _channel = MethodChannel('com.resonance/equalizer');

class EqualizerPreset {
  final String name;
  final List<int> levels; // one per band, in mB
  const EqualizerPreset(this.name, this.levels);
}

// 5-band presets (values in millibels)
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
  RxInt bassBoost = 0.obs; // 0–1000
  RxInt gain = 0.obs; // 0–1200 mB (pre-amp)
  RxInt virtualizer = 0.obs; // 0–1000
  RxInt selectedPreset = 0.obs;
  RxInt numBands = 5.obs;
  RxList<int> centerFreqs = <int>[].obs; // Hz × 1000
  RxInt minLevel = (-1500).obs;
  RxInt maxLevel = 1500.obs;

  List<EqualizerPreset> get presets => _presets;

  Future<void> init(int audioSessionId) async {
    try {
      await _channel.invokeMethod('init', {'sessionId': audioSessionId});
      numBands.value = await _channel.invokeMethod('getNumBands') ?? 5;
      final range = await _channel.invokeMethod('getBandLevelRange') as List?;
      if (range != null && range.length == 2) {
        minLevel.value = range[0] as int;
        maxLevel.value = range[1] as int;
      }
      // Fetch center frequencies
      final freqs = <int>[];
      for (int i = 0; i < numBands.value; i++) {
        final f = await _channel.invokeMethod('getBandCenterFreq', {'band': i})
                as int? ??
            0;
        freqs.add(f);
      }
      centerFreqs.assignAll(freqs);
      // Fetch current levels
      final lvls = <int>[];
      for (int i = 0; i < numBands.value; i++) {
        final l =
            await _channel.invokeMethod('getBandLevel', {'band': i}) as int? ??
                0;
        lvls.add(l);
      }
      levels.assignAll(lvls);
    } catch (e) {
      // EQ not supported on this device — silently degrade
      debugPrint('EQ init failed: $e');
    }
  }

  Future<void> setBandLevel(int band, int levelMillibels) async {
    if (band < 0 || band >= levels.length) return;
    levels[band] = levelMillibels;
    await _channel
        .invokeMethod('setBandLevel', {'band': band, 'level': levelMillibels});
  }

  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    await _channel.invokeMethod('setEqEnabled', {'enabled': value});
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
    bassBoost.value = strength.clamp(0, 1000);
    await _channel.invokeMethod('setBassBoost', {'strength': bassBoost.value});
  }

  Future<void> setGain(int gainMillibels) async {
    gain.value = gainMillibels.clamp(0, 1200);
    await _channel.invokeMethod('setGain', {'gain': gain.value});
  }

  Future<void> setVirtualizer(int strength) async {
    virtualizer.value = strength.clamp(0, 1000);
    await _channel
        .invokeMethod('setVirtualizer', {'strength': virtualizer.value});
  }

  Future<void> release() => _channel.invokeMethod('release');

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
