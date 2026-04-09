package com.resonance.resonance

import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.Virtualizer
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

            "getNumBands" -> result.success(equalizer?.numberOfBands?.toInt() ?: 0)

            "getBandLevelRange" -> {
                val range = equalizer?.bandLevelRange
                result.success(
                    listOf(
                        range?.get(0)?.toInt() ?: -1500,
                        range?.get(1)?.toInt() ?: 1500
                    )
                )
            }

            "getBandCenterFreq" -> {
                val band = call.argument<Int>("band") ?: 0
                result.success(
                    equalizer?.getCenterFreq(band.toShort())?.toInt() ?: 0
                )
            }

            "getBandLevel" -> {
                val band = call.argument<Int>("band") ?: 0
                result.success(
                    equalizer?.getBandLevel(band.toShort())?.toInt() ?: 0
                )
            }

            "setBandLevel" -> {
                val band = call.argument<Int>("band") ?: 0
                val level = call.argument<Int>("level") ?: 0
                try {
                    equalizer?.setBandLevel(band.toShort(), level.toShort())
                    result.success(null)
                } catch (e: Exception) {
                    result.error("SET_BAND_FAILED", e.message, null)
                }
            }

            "setEqEnabled" -> {
                val isEnabled = call.argument<Boolean>("enabled") ?: true
                equalizer?.enabled = isEnabled
                bassBoost?.enabled = isEnabled
                loudnessEnhancer?.enabled = isEnabled
                virtualizer?.enabled = isEnabled
                result.success(null)
            }

            "setBassBoost" -> {
                val strength = call.argument<Int>("strength") ?: 0
                try {
                    bassBoost?.setStrength(strength.toShort())
                    bassBoost?.enabled = strength > 0
                    result.success(null)
                } catch (e: Exception) {
                    result.error("BASS_BOOST_FAILED", e.message, null)
                }
            }

            "getBassBoost" -> result.success(bassBoost?.roundedStrength?.toInt() ?: 0)

            "setGain" -> {
                val gain = call.argument<Int>("gain") ?: 0
                try {
                    loudnessEnhancer?.setTargetGain(gain)
                    loudnessEnhancer?.enabled = gain > 0
                    result.success(null)
                } catch (e: Exception) {
                    result.error("GAIN_FAILED", e.message, null)
                }
            }

            "getGain" -> result.success(
                loudnessEnhancer?.targetGain?.toInt() ?: 0
            )

            "setVirtualizer" -> {
                val strength = call.argument<Int>("strength") ?: 0
                try {
                    virtualizer?.setStrength(strength.toShort())
                    virtualizer?.enabled = strength > 0
                    result.success(null)
                } catch (e: Exception) {
                    result.error("VIRTUALIZER_FAILED", e.message, null)
                }
            }

            "getVirtualizer" -> result.success(
                virtualizer?.roundedStrength?.toInt() ?: 0
            )

            "release" -> {
                release()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun release() {
        safeRelease { equalizer?.release() }
        safeRelease { bassBoost?.release() }
        safeRelease { loudnessEnhancer?.release() }
        safeRelease { virtualizer?.release() }
        equalizer = null
        bassBoost = null
        loudnessEnhancer = null
        virtualizer = null
    }

    private inline fun safeRelease(block: () -> Unit) {
        try { block() } catch (e: Exception) {
            // AudioEffect.release() can throw if the audio session
            // is already gone (e.g. app backgrounded by system).
            // Non-fatal — null assignment below cleans up the reference.
        }
    }
}