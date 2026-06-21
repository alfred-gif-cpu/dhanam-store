import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const DhanamStoreApp());
}

class DhanamStoreApp extends StatelessWidget {
  const DhanamStoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dhanam Store',
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),
      home: const HomeScreen(),
    );
  }
}