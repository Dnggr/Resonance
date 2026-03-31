import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'core/theme/app_theme.dart';
import 'features/player/screens/player_screen.dart';

void main() {
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
      home: const PlayerScreen(),
    );
  }
}
