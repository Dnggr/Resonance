package com.resonance.app

import android.media.audiofx.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class EqualizerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var virtualizer: Virtualizer? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.resonance/equalizer")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        release()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {

            // ── Init all effects for a given audio session ───────────
            "init" -> {
                val sessionId = call.argument<Int>("sessionId") ?: 0
                try {
                    release()
                    equalizer = Equalizer(0, sessionId).apply { enabled = true }
                    bassBoost = BassBoost(0, sessionId).apply { enabled = true }
                    loudnessEnhancer = LoudnessEnhancer(sessionId).apply { enabled = true }
                    virtualizer = Virtualizer(0, sessionId).apply { enabled = true }
                    result.success(null)
                } catch (e: Exception) {
                    result.error("INIT_FAILED", e.message, null)
                }
            }

            // ── EQ ───────────────────────────────────────────────────
            "getNumBands" -> result.success(equalizer?.numberOfBands?.toInt() ?: 0)

            "getBandLevelRange" -> {
                val range = equalizer?.bandLevelRange
                result.success(listOf(range?.get(0)?.toInt() ?: -1500,
                                      range?.get(1)?.toInt() ?: 1500))
            }

            "getBandCenterFreq" -> {
                val band = call.argument<Int>("band") ?: 0
                result.success(equalizer?.getCenterFreq(band.toShort())?.toInt() ?: 0)
            }

            "getBandLevel" -> {
                val band = call.argument<Int>("band") ?: 0
                result.success(equalizer?.getBandLevel(band.toShort())?.toInt() ?: 0)
            }

            "setBandLevel" -> {
                val band  = call.argument<Int>("band")  ?: 0
                val level = call.argument<Int>("level") ?: 0
                equalizer?.setBandLevel(band.toShort(), level.toShort())
                result.success(null)
            }

            "setEqEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                equalizer?.enabled = enabled
                result.success(null)
            }

            // ── Bass Boost ───────────────────────────────────────────
            "setBassBoost" -> {
                val strength = call.argument<Int>("strength") ?: 0   // 0–1000
                bassBoost?.setStrength(strength.toShort())
                bassBoost?.enabled = strength > 0
                result.success(null)
            }

            "getBassBoost" -> result.success(bassBoost?.roundedStrength?.toInt() ?: 0)

            // ── Loudness Enhancer (Pre-amp / Gain) ───────────────────
            "setGain" -> {
                val gain = call.argument<Int>("gain") ?: 0            // 0–1200 mB
                loudnessEnhancer?.setTargetGain(gain)
                loudnessEnhancer?.enabled = gain > 0
                result.success(null)
            }

            "getGain" -> result.success(
                loudnessEnhancer?.targetGain?.toInt() ?: 0
            )

            // ── Virtualizer (Surround) ───────────────────────────────
            "setVirtualizer" -> {
                val strength = call.argument<Int>("strength") ?: 0    // 0–1000
                virtualizer?.setStrength(strength.toShort())
                virtualizer?.enabled = strength > 0
                result.success(null)
            }

            "getVirtualizer" -> result.success(virtualizer?.roundedStrength?.toInt() ?: 0)

            // ── Release ──────────────────────────────────────────────
            "release" -> { release(); result.success(null) }

            else -> result.notImplemented()
        }
    }

    private fun release() {
        try { equalizer?.release() }       catch (_: Exception) {}
        try { bassBoost?.release() }       catch (_: Exception) {}
        try { loudnessEnhancer?.release() } catch (_: Exception) {}
        try { virtualizer?.release() }     catch (_: Exception) {}
        equalizer = null
        bassBoost = null
        loudnessEnhancer = null
        virtualizer = null
    }
}