// android/app/src/main/kotlin/com/resonance/resonance/MainActivity.kt
// MUST extend FlutterFragmentActivity — audio_service checks for this
// at runtime and throws IllegalStateException if it finds FlutterActivity

package com.resonance.resonance

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(EqualizerPlugin())
        flutterEngine.plugins.add(MediaScannerPlugin())
    }
}