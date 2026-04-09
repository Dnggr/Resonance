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

bool _audioServiceInitialized = false;
ResonanceAudioHandler? _audioHandler;

// Created once here, passed to both handler and controller.
// Never recreated — that would break the EQ audio session link.
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

  Get.put(DownloaderService());
  Get.put(PlaylistController());
  Get.put(EqualizerController());
  // PlayerController registered in AppBootstrap._boot() after audio_service init

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
            'audio_service timed out — check AndroidManifest.xml:\n'
            'Service needs android:foregroundServiceType="mediaPlayback"\n'
            'and MainActivity must extend FlutterFragmentActivity',
          ),
        );
        _audioServiceInitialized = true;
      }

      if (!Get.isRegistered<PlayerController>()) {
        Get.put(PlayerController.withHandler(_sharedPlayer, _audioHandler!));
      }

      if (mounted) setState(() => _ready = true);
    } catch (e) {
      debugPrint('Boot error: $e');
      if (e.toString().contains('_cacheManager')) {
        _audioServiceInitialized = true;
        if (!Get.isRegistered<PlayerController>() && _audioHandler != null) {
          Get.put(PlayerController.withHandler(_sharedPlayer, _audioHandler!));
        }
        if (mounted) setState(() => _ready = true);
        return;
      }
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D0D0D),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Color(0xFFE94560), size: 56),
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
                  onPressed: _boot,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_ready) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0D0D),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF6C63FF)),
              SizedBox(height: 20),
              Text('Starting Resonance...',
                  style: TextStyle(color: Colors.white38, fontSize: 14)),
            ],
          ),
        ),
      );
    }

    return const MainShell();
  }
}

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
        backgroundColor: const Color(0xFF1A1A2E),
        selectedIndex: _index,
        indicatorColor: const Color(0xFF6C63FF).withOpacity(0.2),
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon:
                Icon(Icons.library_music_rounded, color: Color(0xFF6C63FF)),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            selectedIcon: Icon(Icons.search_rounded, color: Color(0xFF6C63FF)),
            label: 'Search',
          ),
        ],
      ),
    );
  }
}
