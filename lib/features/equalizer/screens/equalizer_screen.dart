import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/equalizer_controller.dart';

class EqualizerScreen extends StatelessWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final eq = Get.find<EqualizerController>();
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Equalizer & Amplifier',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        actions: [
          Obx(() => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(eq.enabled.value ? 'On' : 'Off',
                      style: TextStyle(
                          color: eq.enabled.value
                              ? AppTheme.primary
                              : Colors.white38,
                          fontSize: 13)),
                  Switch(
                    value: eq.enabled.value,
                    activeColor: AppTheme.primary,
                    onChanged: eq.setEnabled,
                  ),
                  const SizedBox(width: 4),
                ],
              )),
        ],
      ),
      body: Obx(() {
        // Show a friendly message if EQ is not available on this device
        // (e.g. some emulators, Bluetooth-only setups)
        if (eq.numBands.value == 0) {
          return const Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.equalizer_rounded, size: 56, color: Colors.white12),
              SizedBox(height: 12),
              Text('EQ not initialized yet',
                  style: TextStyle(color: Colors.white54, fontSize: 15)),
              SizedBox(height: 6),
              Text('Play a song first, then return here',
                  style: TextStyle(color: Colors.white30, fontSize: 13)),
            ]),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionTitle('Presets'),
            const SizedBox(height: 10),
            _PresetChips(eq: eq),
            const SizedBox(height: 24),
            _sectionTitle('Equalizer'),
            const SizedBox(height: 12),
            _EQBands(eq: eq),
            const SizedBox(height: 24),
            _sectionTitle('Bass Boost'),
            const SizedBox(height: 8),
            _EffectSlider(
              label: 'Strength',
              unit: '',
              value: eq.bassBoost,
              min: 0,
              max: 1000,
              color: Colors.deepOrangeAccent,
              enabled: eq.enabled.value,
              onChanged: (v) => eq.setBassBoost(v.round()),
            ),
            const SizedBox(height: 24),
            _sectionTitle('Pre-amp (Gain)'),
            const SizedBox(height: 8),
            _EffectSlider(
              label: 'Boost',
              unit: ' mB',
              value: eq.gain,
              min: 0,
              max: 1200,
              color: AppTheme.primary,
              enabled: eq.enabled.value,
              onChanged: (v) => eq.setGain(v.round()),
            ),
            const SizedBox(height: 24),
            _sectionTitle('Virtualizer (Surround)'),
            const SizedBox(height: 8),
            _EffectSlider(
              label: 'Strength',
              unit: '',
              value: eq.virtualizer,
              min: 0,
              max: 1000,
              color: Colors.purpleAccent,
              enabled: eq.enabled.value,
              onChanged: (v) => eq.setVirtualizer(v.round()),
            ),
            const SizedBox(height: 32),
          ]),
        );
      }),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15));
}

class _PresetChips extends StatelessWidget {
  final EqualizerController eq;
  const _PresetChips({required this.eq});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(eq.presets.length, (i) {
            final selected = eq.selectedPreset.value == i;
            return GestureDetector(
              onTap: eq.enabled.value ? () => eq.applyPreset(i) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.primary.withOpacity(0.2)
                      : AppTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? AppTheme.primary
                        : Colors.white.withOpacity(0.1),
                  ),
                ),
                child: Text(eq.presets[i].name,
                    style: TextStyle(
                        color: !eq.enabled.value
                            ? Colors.white24
                            : selected
                                ? AppTheme.primary
                                : Colors.white54,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13)),
              ),
            );
          }),
        ));
  }
}

class _EQBands extends StatelessWidget {
  final EqualizerController eq;
  const _EQBands({required this.eq});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final n = eq.numBands.value;
      final isEnabled = eq.enabled.value;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(n, (i) {
            final freq = eq.centerFreqs.length > i
                ? eq.freqLabel(eq.centerFreqs[i])
                : '${i + 1}';
            final level = eq.levels.length > i ? eq.levels[i] : 0;
            final minL = eq.minLevel.value.toDouble();
            final maxL = eq.maxLevel.value.toDouble();

            return Expanded(
              child: Column(children: [
                Text(
                  '${level > 0 ? '+' : ''}${(level / 100).toStringAsFixed(0)}',
                  style: TextStyle(
                    color: !isEnabled
                        ? Colors.white24
                        : level > 0
                            ? AppTheme.primary
                            : level < 0
                                ? AppTheme.accent
                                : Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 160,
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 7),
                        overlayShape: SliderComponentShape.noOverlay,
                        activeTrackColor:
                            isEnabled ? AppTheme.primary : Colors.white24,
                        inactiveTrackColor: Colors.white12,
                        thumbColor:
                            isEnabled ? AppTheme.primary : Colors.white24,
                        disabledActiveTrackColor: Colors.white24,
                        disabledThumbColor: Colors.white24,
                      ),
                      child: Slider(
                        value: level.toDouble().clamp(minL, maxL),
                        min: minL,
                        max: maxL,
                        divisions: ((maxL - minL) / 100).round(),
                        onChanged: isEnabled
                            ? (v) => eq.setBandLevel(i, v.round())
                            : null,
                      ),
                    ),
                  ),
                ),
                Text(freq,
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 10)),
              ]),
            );
          }),
        ),
      );
    });
  }
}

class _EffectSlider extends StatelessWidget {
  final String label;
  final String unit;
  final RxInt value;
  final int min;
  final int max;
  final Color color;
  final bool enabled;
  final Function(double) onChanged;

  const _EffectSlider({
    required this.label,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(label,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                          Text('${value.value}$unit',
                              style: TextStyle(
                                  color: enabled ? color : Colors.white24,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ]),
                    const SizedBox(height: 4),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 7),
                        overlayShape: SliderComponentShape.noOverlay,
                        activeTrackColor: enabled ? color : Colors.white24,
                        inactiveTrackColor: Colors.white12,
                        thumbColor: enabled ? color : Colors.white24,
                        disabledActiveTrackColor: Colors.white24,
                        disabledThumbColor: Colors.white24,
                      ),
                      child: Slider(
                        value: value.value.toDouble(),
                        min: min.toDouble(),
                        max: max.toDouble(),
                        onChanged: enabled ? onChanged : null,
                      ),
                    ),
                  ]),
            ),
          ]),
        ));
  }
}
