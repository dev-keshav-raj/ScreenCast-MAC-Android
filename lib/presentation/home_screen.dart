import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'macos_host_view.dart';
import 'android_receiver_view.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const Scaffold(
        body: Center(child: Text('Web platform not supported by MacMirror')),
      );
    }
    
    if (Platform.isMacOS) {
      return const MacosHostView();
    } else if (Platform.isAndroid) {
      return const AndroidReceiverView();
    } else {
      return Scaffold(
        body: Center(
          child: Text('Platform ${Platform.operatingSystem} is not supported by MacMirror.'),
        ),
      );
    }
  }
}
