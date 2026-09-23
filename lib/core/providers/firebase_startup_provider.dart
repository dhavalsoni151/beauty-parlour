import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firebase_service.dart';

const firebaseOrganizationId = 'priyanka-beauty-parlour';

enum FirebaseStartupState {
  initializing,
  unauthenticated,
  checkingMembership,
  checkingConnectivity,
  ready,
  accessDenied,
  offline,
  error,
}

class FirebaseStartupProvider extends ChangeNotifier {
  FirebaseStartupProvider({
    FirebaseStartupBackend? backend,
    String? firebaseInitError,
  }) : _backend =
           backend ??
           FirebaseStartupBackend.fromService(FirebaseService.instance),
       _initError = firebaseInitError;

  final FirebaseStartupBackend _backend;
  final String? _initError;
  FirebaseStartupState _state = FirebaseStartupState.initializing;
  String? _errorMessage;

  FirebaseStartupState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isReady => _state == FirebaseStartupState.ready;
  String? get userUid => _backend.currentUserUid;

  Future<void> checkStartup() async {
    _setState(FirebaseStartupState.initializing);
    // Firebase SDK itself failed to start (e.g. no network on cold start,
    // App Check failure, unsupported platform). Surface it instead of
    // hanging on the splash/loading screen.
    if (_initError != null) {
      _errorMessage = _initError;
      _setState(FirebaseStartupState.error);
      return;
    }
    try {
      final uid = _backend.currentUserUid;
      if (uid == null) {
        _setState(FirebaseStartupState.unauthenticated);
        return;
      }
      await _checkAuthorizedUser(uid);
    } on FirebaseOnlineException catch (error) {
      _errorMessage = error.message;
      _setState(FirebaseStartupState.offline);
    } on FirebaseException catch (error) {
      _errorMessage = _firebaseErrorMessage(error);
      _setState(FirebaseStartupState.error);
    } catch (error) {
      _errorMessage = error.toString();
      _setState(FirebaseStartupState.error);
    }
  }

  Future<void> signIn(String email, String password) async {
    _setState(FirebaseStartupState.initializing);
    try {
      final uid = await _backend.signIn(email, password);
      await _checkAuthorizedUser(uid);
    } on FirebaseOnlineException catch (error) {
      _errorMessage = error.message;
      _setState(FirebaseStartupState.offline);
    } on FirebaseAuthException catch (error) {
      _errorMessage = _authErrorMessage(error);
      _setState(FirebaseStartupState.unauthenticated);
    } on FirebaseException catch (error) {
      _errorMessage = _firebaseErrorMessage(error);
      _setState(FirebaseStartupState.error);
    } catch (error) {
      _errorMessage = error.toString();
      _setState(FirebaseStartupState.error);
    }
  }

  Future<void> signOut() async {
    await _backend.signOut();
    _errorMessage = null;
    _setState(FirebaseStartupState.unauthenticated);
  }

  Future<void> _checkAuthorizedUser(String? uid) async {
    if (uid == null) {
      _setState(FirebaseStartupState.unauthenticated);
      return;
    }
    _setState(FirebaseStartupState.checkingMembership);
    final role = await _backend.memberRole(uid);
    if (role == null) {
      _errorMessage = 'Your account is not authorized for this organization.';
      _setState(FirebaseStartupState.accessDenied);
      return;
    }

    if (role != 'owner' && role != 'admin' && role != 'staff') {
      _errorMessage =
          'Your account does not have an allowed organization role.';
      _setState(FirebaseStartupState.accessDenied);
      return;
    }

    _setState(FirebaseStartupState.checkingConnectivity);
    await _backend.requireOnline();
    _errorMessage = null;
    _setState(FirebaseStartupState.ready);
  }

  void _setState(FirebaseStartupState state) {
    _state = state;
    notifyListeners();
  }

  String _authErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Email or password is incorrect.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return error.message ?? 'Unable to sign in. Please try again.';
    }
  }

  String _firebaseErrorMessage(FirebaseException error) =>
      error.message ?? 'Firebase is unavailable. Please try again.';
}

abstract class FirebaseStartupBackend {
  String? get currentUserUid;
  Future<String?> signIn(String email, String password);
  Future<String?> memberRole(String uid);
  Future<void> requireOnline();
  Future<void> signOut();

  factory FirebaseStartupBackend.fromService(FirebaseService service) =>
      _FirebaseServiceStartupBackend(service);
}

class _FirebaseServiceStartupBackend implements FirebaseStartupBackend {
  final FirebaseService service;
  _FirebaseServiceStartupBackend(this.service);

  @override
  String? get currentUserUid => service.auth.currentUser?.uid;

  @override
  Future<String?> signIn(String email, String password) async {
    final credential = await service.signIn(email: email, password: password);
    return credential.user?.uid;
  }

  @override
  Future<String?> memberRole(String uid) async {
    try {
      final member = await service.firestore
          .collection('organizations')
          .doc(firebaseOrganizationId)
          .collection('members')
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw const FirebaseOnlineException(
              'Firebase is taking too long to respond. Check your connection and retry.',
            ),
          );
      final data = member.data();
      if (!member.exists || data == null) return null;
      return data['role'] as String?;
    } on FirebaseException {
      await service.requireOnline();
      rethrow;
    }
  }

  @override
  Future<void> requireOnline() => service.requireOnline();

  @override
  Future<void> signOut() => service.signOut();
}
