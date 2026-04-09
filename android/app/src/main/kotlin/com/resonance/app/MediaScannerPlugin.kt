package com.resonance.app

import android.media.MediaScannerConnection
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MediaScannerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var binding: FlutterPlugin.FlutterPluginBinding

    override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
        binding = b
        channel = MethodChannel(b.binaryMessenger, "com.resonance/media_scanner")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "scanFile") {
            val path = call.argument<String>("path") ?: return result.success(null)
            MediaScannerConnection.scanFile(binding.applicationContext, arrayOf(path), null) { _, _ -> }
            result.success(null)
        } else {
            result.notImplemented()
        }
    }
}