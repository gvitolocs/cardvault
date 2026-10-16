import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return web;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDlbKXeR0R3aAATZtCG6dhEPUw39DhXQpU',
    appId: '1:36941064114:web:e6ca84f2723df9ee71e6ab',
    messagingSenderId: '36941064114',
    projectId: 'pokoin',
    authDomain: 'pokoin.firebaseapp.com',
    storageBucket: 'pokoin.firebasestorage.app',
    measurementId: 'G-6H4VHXX1PX',
  );

  // Configurazione dell'app Android com.vitologic.pokoin nel medesimo progetto.
  // Mantenerla allineata ad android/app/google-services.json.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCu1pg84O8C_EeFHDukCLbuq137BLK-N40',
    appId: '1:36941064114:android:b21dbb3efb235aa471e6ab',
    messagingSenderId: '36941064114',
    projectId: 'pokoin',
    storageBucket: 'pokoin.firebasestorage.app',
  );
}
