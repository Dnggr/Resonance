package com.resonance.resonance

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

// ─── FIX: Must extend AudioServiceActivity, NOT FlutterFragmentActivity ───────
// When MainActivity extends FlutterFragmentActivity, audio_service cannot attach
// its MediaSession to the activity. The foreground service notification requires
// the activity to be an AudioServiceActivity so the MediaSession token is
// properly registered with Android. Without this, the lock-screen / notification
// player shows blank or never appears at all.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(EqualizerPlugin())
        flutterEngine.plugins.add(MediaScannerPlugin())
    }
}