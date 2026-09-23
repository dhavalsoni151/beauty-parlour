import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../firebase_options.dart';

class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  late final FirebaseAuth auth;
  late final FirebaseFirestore firestore;
  final Connectivity connectivity = Connectivity();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    auth = FirebaseAuth.instance;
    firestore = FirebaseFirestore.instance;
    firestore.settings = const Settings(persistenceEnabled: false);
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
    );
    _initialized = true;
  }

  Future<void> requireOnline() async {
    final connectivityResult = await connectivity.checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      throw const FirebaseOnlineException('Internet connection is required.');
    }

    try {
      await firestore
          .collection('_system')
          .doc('health')
          .get(const GetOptions(source: Source.server));
    } on FirebaseException catch (error) {
      throw FirebaseOnlineException(
        error.message ?? 'Firebase is unavailable. Check your connection.',
      );
    }
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    return auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() => auth.signOut();
}

class FirebaseOnlineException implements Exception {
  final String message;
  const FirebaseOnlineException(this.message);

  @override
  String toString() => message;
}
