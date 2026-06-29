import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return android;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCcijpJVlG64I1kDKIuuXD_aNf5BlOVhhI',
    appId: '1:549190182924:web:YOUR_WEB_APP_ID',
    messagingSenderId: '549190182924',
    projectId: 'dhanam-store',
    storageBucket: 'dhanam-store.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCcijpJVlG64I1kDKIuuXD_aNf5BlOVhhI',
    appId: '1:549190182924:android:6a06eb4823a30e9fca6629',
    messagingSenderId: '549190182924',
    projectId: 'dhanam-store',
    storageBucket: 'dhanam-store.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCcijpJVlG64I1kDKIuuXD_aNf5BlOVhhI',
    appId: '1:549190182924:ios:YOUR_IOS_APP_ID',
    messagingSenderId: '549190182924',
    projectId: 'dhanam-store',
    storageBucket: 'dhanam-store.firebasestorage.app',
    iosBundleId: 'com.dhanamstore.app',
  );
}
