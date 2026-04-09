// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'core/models/playlist_model.dart';
import 'core/models/download_record.dart';
import 'core/theme/app_theme.dart';
import 'core/services/audio_handler.dart';
import 'features/player/screens/player_screen.dart';
import 'features/downloader/screens/search_screen.dart';
import 'features/downloader/services/downloader_service.dart';
import 'features/player/controllers/player_controller.dart';
import 'features/playlist/controllers/playlist_controller.dart';
import 'features/equalizer/controllers/equalizer_controller.dart';

// ── Process-level singletons ────────────────────────────────────────────────
// These survive hot restart. Never re-create them.
bool _audioServiceInitialized = false;
ResonanceAudioHandler? _audioHandler;

// One AudioPlayer shared by handler + controller.
// TRAP: Do NOT create this inside a function or class — it must be
// module-level so it's never garbage collected or recreated.
// If you create a new AudioPlayer after EQ init, the session ID changes
// and EQ stops working.
final AudioPlayer _sharedPlayer = AudioPlayer();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await Hive.initFlutter();
  Hive.registerAdapter(PlaylistModelAdapter());
  Hive.registerAdapter(DownloadRecordAdapter());
  await Hive.openBox<PlaylistModel>('playlists');
  await Hive.openBox<DownloadRecord>('downloads');

  // Register everything that does NOT need audio_service.
  // These are safe to init before runApp().
  // TRAP: Use isRegistered guard — hot restart can call main() again
  // without clearing GetX, which would throw "already registered".
  if (!Get.isRegistered<DownloaderService>()) Get.put(DownloaderService());
  if (!Get.isRegistered<PlaylistController>()) Get.put(PlaylistController());
  if (!Get.isRegistered<EqualizerController>()) Get.put(EqualizerController());

  // TRAP: Do NOT register PlayerController here.
  // It needs the shared AudioPlayer + handler from audio_service.
  // Registering it here with a plain AudioPlayer would create a SECOND
  // AudioPlayer, and then withHandler() would fail with "already registered".

  runApp(const ResonanceApp());
}

class ResonanceApp extends StatelessWidget {
  const ResonanceApp({super.key});
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Resonance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AppBootstrap(),
    );
  }
}

// ── AppBootstrap ────────────────────────────────────────────────────────────
// Initializes audio_service AFTER the UI starts rendering.
// Shows a spinner instead of freezing on the Flutter logo.
// TRAP: Never call AudioService.init() in main() — it can hang
// the splash screen for 5–12 seconds on first install.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});
  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    if (mounted) setState(() => _error = null);

    try {
      // ── TRAP: Singleton guard ──────────────────────────────────────────
      // AudioService is a process-level singleton (not just app-level).
      // Calling init() a second time (e.g. on hot restart) throws:
      // "Failed assertion: '_cacheManager == null': is not true"
      // The bool flag prevents this.
      if (!_audioServiceInitialized) {
        _audioHandler = await AudioService.init(
          builder: () => ResonanceAudioHandler(_sharedPlayer),
          config: const AudioServiceConfig(
            androidNotificationChannelId: 'com.resonance.audio',
            androidNotificationChannelName: 'Resonance Player',
            androidNotificationOngoing: true,
            androidShowNotificationBadge: true,
            androidNotificationIcon: 'mipmap/ic_launcher',
          ),
        ).timeout(
          const Duration(seconds: 12),
          onTimeout: () => throw Exception(
            'audio_service init timed out (12s).\n\n'
            'Most likely causes:\n'
            '1. MainActivity still extends FlutterActivity\n'
            '   → Change to FlutterFragmentActivity\n'
            '2. AudioService not declared in AndroidManifest.xml\n'
            '   → Add the <service> block with foregroundServiceType\n'
            '3. Run: cd android && ./gradlew clean && cd .. && flutter clean',
          ),
        );
        _audioServiceInitialized = true;
      }

      // Register PlayerController only after handler is confirmed ready
      if (!Get.isRegistered<PlayerController>()) {
        Get.put(PlayerController.withHandler(_sharedPlayer, _audioHandler!));
      }

      if (mounted) setState(() => _ready = true);
    } catch (e) {
      debugPrint('Boot error: $e');

      // ── TRAP: _cacheManager assertion = service already running ────────
      // This happens on hot restart. The service is actually fine.
      // Mark as initialized and proceed normally.
      if (e.toString().contains('_cacheManager')) {
        _audioServiceInitialized = true;
        if (!Get.isRegistered<PlayerController>() && _audioHandler != null) {
          Get.put(PlayerController.withHandler(_sharedPlayer, _audioHandler!));
        } else if (!Get.isRegistered<PlayerController>()) {
          // Handler ref lost on hot restart — fall back to no-service mode
          Get.put(PlayerController());
        }
        if (mounted) setState(() => _ready = true);
        return;
      }

      // ── TRAP: IllegalStateException = wrong Activity class ─────────────
      // audio_service failed entirely. Register a fallback PlayerController
      // WITHOUT audio_service so the library and search screens still work.
      // The user loses lock-screen controls but the app doesn't crash.
      if (!Get.isRegistered<PlayerController>()) {
        Get.put(PlayerController()); // fallback: no background service
      }

      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── Error screen ──────────────────────────────────────────────────────
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppTheme.accent, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'Audio service failed to start',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Music playback still works — lock screen controls unavailable',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontFamily: 'monospace'),
                    textAlign: TextAlign.left,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _boot,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white),
                    ),
                    // Continue without lock screen controls
                    OutlinedButton.icon(
                      onPressed: () {
                        if (mounted) setState(() => _ready = true);
                      },
                      icon: const Icon(Icons.music_note_rounded,
                          size: 18, color: Colors.white54),
                      label: const Text('Continue anyway',
                          style: TextStyle(color: Colors.white54)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Loading screen ────────────────────────────────────────────────────
    if (!_ready) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              SizedBox(height: 20),
              Text(
                'Starting Resonance...',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return const MainShell();
  }
}

// ── MainShell ───────────────────────────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  static const List<Widget> _screens = [PlayerScreen(), SearchScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppTheme.surface,
        selectedIndex: _index,
        indicatorColor: AppTheme.primary.withOpacity(0.2),
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon:
                Icon(Icons.library_music_rounded, color: AppTheme.primary),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            selectedIcon: Icon(Icons.search_rounded, color: AppTheme.primary),
            label: 'Search',
          ),
        ],
      ),
    );
  }
}
