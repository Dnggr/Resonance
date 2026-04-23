import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'core/models/playlist_model.dart';
import 'core/models/download_record.dart';
import 'core/models/song_metadata.dart';
import 'core/theme/app_theme.dart';
import 'core/services/audio_handler.dart';
import 'core/services/metadata_service.dart';
import 'features/player/screens/player_screen.dart';
import 'features/downloader/screens/search_screen.dart';
import 'features/downloader/services/downloader_service.dart';
import 'features/player/controllers/player_controller.dart';
import 'features/playlist/controllers/playlist_controller.dart';
import 'features/equalizer/controllers/equalizer_controller.dart';

bool _audioServiceInitialized = false;
ResonanceAudioHandler? _audioHandler;
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
  Hive.registerAdapter(SongMetadataAdapter());

  await Hive.openBox<PlaylistModel>('playlists');
  await Hive.openBox<DownloadRecord>('downloads');
  await Hive.openBox<SongMetadata>('song_metadata');

  if (!Get.isRegistered<DownloaderService>()) Get.put(DownloaderService());
  if (!Get.isRegistered<PlaylistController>()) Get.put(PlaylistController());
  if (!Get.isRegistered<EqualizerController>()) Get.put(EqualizerController());
  if (!Get.isRegistered<MetadataService>()) Get.put(MetadataService());

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
          // REMOVE 'const' because we are doing logic-based configuration
          config: const AudioServiceConfig(
            androidNotificationChannelId: 'com.resonance.audio',
            androidNotificationChannelName: 'Resonance Player',

            // Fix the conflict: If stopping foreground on pause, this must be false
            androidNotificationOngoing: false,
            androidShowNotificationBadge: true,
            androidNotificationIcon: 'mipmap/ic_launcher',

            androidStopForegroundOnPause: false,

            // COMMENT OUT or REMOVE this line if the package version doesn't support it
            // androidNotificationClickActivatesTask: true,

            preloadArtwork: true,
          ),
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw Exception('audio_service init timed out'),
        );

        _audioServiceInitialized = true;

        // ─── Configure audio session for music ───────────────────────────
        // This tells Android this is a music app so the OS treats it
        // differently from alarms/ringtones and allows background audio.
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());

        // ─── FIX: Request audio focus with GAIN (long-running playback) ──
        // Requesting focus here rather than only on first play ensures
        // Android registers this as a media app, improving notification
        // visibility and preventing Doze from treating it as idle.
        await session.setActive(true);
      }

      if (!Get.isRegistered<PlayerController>()) {
        Get.put(PlayerController.withHandler(_sharedPlayer, _audioHandler!));
      }

      if (mounted) setState(() => _ready = true);
    } catch (e) {
      debugPrint('Boot error: $e');

      if (e.toString().contains('_cacheManager')) {
        _audioServiceInitialized = true;
        if (!Get.isRegistered<PlayerController>()) {
          if (_audioHandler != null) {
            Get.put(
                PlayerController.withHandler(_sharedPlayer, _audioHandler!));
          } else {
            Get.put(PlayerController());
          }
        }
        if (mounted) setState(() => _ready = true);
        return;
      }

      if (!Get.isRegistered<PlayerController>()) {
        Get.put(PlayerController());
      }

      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _continueWithoutService() {
    if (mounted)
      setState(() {
        _error = null;
        _ready = true;
      });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Colors.orangeAccent, size: 56),
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
                  'Music playback still works.\nLock screen controls may be unavailable.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                  textAlign: TextAlign.center,
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
                    OutlinedButton.icon(
                      onPressed: _continueWithoutService,
                      icon: const Icon(Icons.music_note_rounded,
                          size: 18, color: Colors.white54),
                      label: const Text('Continue',
                          style: TextStyle(color: Colors.white54)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Show error details',
                      style: TextStyle(color: Colors.white24, fontSize: 12)),
                  iconColor: Colors.white24,
                  collapsedIconColor: Colors.white24,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                              fontFamily: 'monospace')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

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
