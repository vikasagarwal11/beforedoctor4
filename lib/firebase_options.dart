// File generated using data from your existing GoogleService-Info.plist
// Firebase project: beforedoctor4
// This file connects to your EXISTING Firebase project (not creating a new one)

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDS8J7TdaC9HhmNrtAlfkmRTGQxlWYMBG4',
    appId: '1:930239596443:android:YOUR_ANDROID_APP_ID', // TODO: Get from Firebase Console
    messagingSenderId: '930239596443',
    projectId: 'beforedoctor4',
    storageBucket: 'beforedoctor4.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDS8J7TdaC9HhmNrtAlfkmRTGQxlWYMBG4',
    appId: '1:930239596443:ios:62e47391423d19d145833e',
    messagingSenderId: '930239596443',
    projectId: 'beforedoctor4',
    storageBucket: 'beforedoctor4.firebasestorage.app',
    iosBundleId: 'com.example.PVReporting',
  );
}
