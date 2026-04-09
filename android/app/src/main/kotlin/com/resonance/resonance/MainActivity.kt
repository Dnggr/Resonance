// android/app/src/main/kotlin/com/resonance/resonance/MainActivity.kt
// Reverted to FlutterActivity — audio_service removed so
// FlutterFragmentActivity is no longer required.

package com.resonance.resonance

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(EqualizerPlugin())
        flutterEngine.plugins.add(MediaScannerPlugin())
    }
}