import 'dart:io';
import 'package:flutter/services.dart';

class MediaScanner {
  static const _channel = MethodChannel('com.resonance/media_scanner');

  /// Notifies Android's MediaStore so the file appears in other music players
  static Future<void> scanFile(String filePath) async {
    try {
      await _channel.invokeMethod('scanFile', {'path': filePath});
    } catch (_) {
      // Non-fatal: file still exists, just may not appear immediately
    }
  }
}
