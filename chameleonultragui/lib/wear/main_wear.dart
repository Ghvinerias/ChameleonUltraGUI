import 'package:flutter/material.dart';

void main() {
  runApp(const WearApp());
}

class WearApp extends StatelessWidget {
  const WearApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: ClipOval(
        child: Scaffold(
          backgroundColor: Colors.black,
          body: const Center(child: Text('Wear OS')),
        ),
      ),
    );
  }
}
