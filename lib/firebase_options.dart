// Generated-like file (manual) to avoid requiring Firebase CLI.
// Source: android/app/google-services.json

import "package:firebase_core/firebase_core.dart" show FirebaseOptions;
import "package:flutter/foundation.dart" show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError("DefaultFirebaseOptions are not configured for web.");
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          "DefaultFirebaseOptions are not configured for this platform.",
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: "AIzaSyARbRMLRxa98vod84K1StftgdkkxjlraVM",
    appId: "1:515769740037:android:d5a4cf6d30c490e958a56c",
    messagingSenderId: "515769740037",
    projectId: "raspisanie-57948",
    storageBucket: "raspisanie-57948.firebasestorage.app",
  );
}

