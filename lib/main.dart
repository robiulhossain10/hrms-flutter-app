import 'package:flutter/material.dart';
import 'screens/splash/splash_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Attendance System',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF06080F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C5CFC),
          secondary: Color(0xFF00E5A0),
          surface: Color(0xFF0E1225),
          onSurface: Color(0xFFF0F2F8),
        ),
        fontFamily: 'Segoe UI',
      ),
      home: const SplashPage(),
    );
  }
}
