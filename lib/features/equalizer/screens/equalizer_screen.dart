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
          Obx(() => Switch(
                value: eq.enabled.value,
                activeColor: AppTheme.primary,
                onChanged: eq.setEnabled,
              )),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Presets ─────────────────────────────────────────
          _sectionTitle('Presets'),
          const SizedBox(height: 10),
          _PresetChips(eq: eq),
          const SizedBox(height: 24),

          // ── EQ Bands ─────────────────────────────────────────
          _sectionTitle('Equalizer'),
          const SizedBox(height: 12),
          _EQBands(eq: eq),
          const SizedBox(height: 24),

          // ── Bass Boost ────────────────────────────────────────
          _sectionTitle('Bass Boost'),
          const SizedBox(height: 8),
          _EffectSlider(
            label: 'Strength',
            unit: '',
            value: eq.bassBoost,
            min: 0,
            max: 1000,
            color: Colors.deepOrangeAccent,
            onChanged: (v) => eq.setBassBoost(v.round()),
          ),
          const SizedBox(height: 24),

          // ── Pre-amp / Gain ────────────────────────────────────
          _sectionTitle('Pre-amp (Gain)'),
          const SizedBox(height: 8),
          _EffectSlider(
            label: 'Boost',
            unit: ' mB',
            value: eq.gain,
            min: 0,
            max: 1200,
            color: AppTheme.primary,
            onChanged: (v) => eq.setGain(v.round()),
          ),
          const SizedBox(height: 24),

          // ── Virtualizer ───────────────────────────────────────
          _sectionTitle('Virtualizer (Surround)'),
          const SizedBox(height: 8),
          _EffectSlider(
            label: 'Strength',
            unit: '',
            value: eq.virtualizer,
            min: 0,
            max: 1000,
            color: Colors.purpleAccent,
            onChanged: (v) => eq.setVirtualizer(v.round()),
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15));
}

// ── Preset chips ─────────────────────────────────────────────
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
              onTap: () => eq.applyPreset(i),
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
                        color: selected ? AppTheme.primary : Colors.white54,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13)),
              ),
            );
          }),
        ));
  }
}

// ── EQ Band Sliders ──────────────────────────────────────────
class _EQBands extends StatelessWidget {
  final EqualizerController eq;
  const _EQBands({required this.eq});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final n = eq.numBands.value;
      if (n == 0) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('EQ not available on this device',
              style: TextStyle(color: Colors.white38)),
        );
      }
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
                    color: level > 0
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
                        activeTrackColor: AppTheme.primary,
                        inactiveTrackColor: Colors.white12,
                        thumbColor: AppTheme.primary,
                      ),
                      child: Slider(
                        value: level.toDouble().clamp(minL, maxL),
                        min: minL,
                        max: maxL,
                        divisions: ((maxL - minL) / 100).round(),
                        onChanged: eq.enabled.value
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

// ── Generic effect slider ────────────────────────────────────
class _EffectSlider extends StatelessWidget {
  final String label;
  final String unit;
  final RxInt value;
  final int min;
  final int max;
  final Color color;
  final Function(double) onChanged;

  const _EffectSlider({
    required this.label,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
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
                                  color: color,
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
                        activeTrackColor: color,
                        inactiveTrackColor: Colors.white12,
                        thumbColor: color,
                      ),
                      child: Slider(
                        value: value.value.toDouble(),
                        min: min.toDouble(),
                        max: max.toDouble(),
                        onChanged: onChanged,
                      ),
                    ),
                  ]),
            ),
          ]),
        ));
  }
}
