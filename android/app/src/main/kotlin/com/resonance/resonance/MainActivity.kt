// android/app/src/main/kotlin/com/resonance/resonance/MainActivity.kt

package com.resonance.resonance

// ⚠️ CRITICAL: Must be FlutterFragmentActivity — NOT FlutterActivity
// audio_service checks this at runtime (AudioServicePlugin.java:460)
// If it finds FlutterActivity it throws IllegalStateException immediately
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(EqualizerPlugin())
        flutterEngine.plugins.add(MediaScannerPlugin())
    }
}