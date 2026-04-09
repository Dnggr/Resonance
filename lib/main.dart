import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/models/playlist_model.dart';
import 'core/models/download_record.dart';
import 'core/theme/app_theme.dart';
import 'core/services/audio_handler.dart';
import 'core/services/notification_service.dart';
import 'features/player/screens/player_screen.dart';
import 'features/downloader/screens/search_screen.dart';
import 'features/downloader/services/downloader_service.dart';
import 'features/player/controllers/player_controller.dart';
import 'features/playlist/controllers/playlist_controller.dart';
import 'features/equalizer/controllers/equalizer_controller.dart';

// Global — set after init completes
ResonanceAudioHandler? audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Hive is fast — keep this here
  await Hive.initFlutter();
  Hive.registerAdapter(PlaylistModelAdapter());
  Hive.registerAdapter(DownloadRecordAdapter());
  await Hive.openBox<PlaylistModel>('playlists');
  await Hive.openBox<DownloadRecord>('downloads');

  // Notifications — fast, keep here
  await NotificationService.init();

  // DO NOT await AudioService.init() here — it hangs the splash
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
      home: const AppBootstrap(), // ← new bootstrap widget
    );
  }
}

/// Initializes audio_service AFTER the UI is rendered,
/// so the splash screen dismisses immediately.
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
    try {
      // Init audio_service with a timeout so it can't hang forever
      audioHandler = await initAudioService().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception(
            'audio_service timed out — check AndroidManifest.xml'),
      );

      // Register all controllers now that handler is ready
      Get.put(PlayerController(audioHandler!));
      Get.put(DownloaderService());
      Get.put(PlaylistController());
      Get.put(EqualizerController());

      if (mounted) setState(() => _ready = true);
    } catch (e) {
      debugPrint('Boot error: $e');
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Error state — shows what went wrong instead of hanging
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
                const Text('Failed to start audio service',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() => _error = null);
                    _boot();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Loading state — brief spinner instead of frozen logo
    if (!_ready) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              SizedBox(height: 20),
              Text('Starting Resonance...',
                  style: TextStyle(color: Colors.white38, fontSize: 14)),
            ],
          ),
        ),
      );
    }

    // Ready — show the real app
    return const MainShell();
  }
}

class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    return _MainShellBody();
  }
}

class _MainShellBody extends StatefulWidget {
  @override
  State<_MainShellBody> createState() => _MainShellBodyState();
}

class _MainShellBodyState extends State<_MainShellBody> {
  int _index = 0;

  static const List<Widget> _screens = [
    PlayerScreen(),
    SearchScreen(),
  ];

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
