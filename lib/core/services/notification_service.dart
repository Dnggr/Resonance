import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _dlChannelId = 'resonance_downloads';
  static const _dlChannelName = 'Downloads';

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));

    // Create the downloads notification channel
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _dlChannelId,
          _dlChannelName,
          description: 'Music download progress',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
        ));
  }

  /// Show or update a download-progress notification.
  /// [id] must be unique per download (use hashCode of videoId+format).
  static Future<void> showDownloadProgress({
    required int id,
    required String title,
    required String author,
    required int percent, // 0–100, or -1 for indeterminate
  }) async {
    await _plugin.show(
      id,
      '⬇ $title',
      percent < 0 ? 'Connecting…' : 'Downloading · $percent%',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _dlChannelId,
          _dlChannelName,
          channelDescription: 'Music download progress',
          importance: Importance.low,
          priority: Priority.low,
          showProgress: true,
          maxProgress: 100,
          progress: percent < 0 ? 0 : percent,
          indeterminate: percent < 0,
          onlyAlertOnce: true,
          ongoing: true,
          autoCancel: false,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  /// Show a "download complete" notification.
  static Future<void> showDownloadDone({
    required int id,
    required String title,
    required String format,
  }) async {
    await _plugin.show(
      id,
      '✓ Download complete',
      '$title  [$format]',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _dlChannelId,
          _dlChannelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          autoCancel: true,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  /// Cancel a specific notification (e.g. when user cancels download).
  static Future<void> cancel(int id) => _plugin.cancel(id);
}
