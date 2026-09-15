import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:beauty_parlour/core/providers/firebase_startup_provider.dart';
import 'package:beauty_parlour/core/firebase/firebase_service.dart';

class _FakeBackend implements FirebaseStartupBackend {
  _FakeBackend({this.uid, this.role, this.online = true});

  String? uid;
  String? role;
  bool online;

  @override
  String? get currentUserUid => uid;

  @override
  Future<String?> signIn(String email, String password) async {
    uid = 'owner-uid';
    return uid;
  }

  @override
  Future<String?> memberRole(String uid) async => role;

  @override
  Future<void> requireOnline() async {
    if (!online) {
      throw const FirebaseOnlineException('Internet connection is required.');
    }
  }

  @override
  Future<void> signOut() async => uid = null;
}

void main() {
  test('unauthenticated user becomes unauthenticated', () async {
    final provider = FirebaseStartupProvider(backend: _FakeBackend());

    await provider.checkStartup();

    expect(provider.state, FirebaseStartupState.unauthenticated);
  });

  test('authenticated member becomes ready', () async {
    final provider = FirebaseStartupProvider(
      backend: _FakeBackend(uid: 'owner-uid', role: 'owner'),
    );

    await provider.checkStartup();

    expect(provider.state, FirebaseStartupState.ready);
  });

  test('authenticated non-member is denied', () async {
    final provider = FirebaseStartupProvider(
      backend: _FakeBackend(uid: 'unknown-uid'),
    );

    await provider.checkStartup();

    expect(provider.state, FirebaseStartupState.accessDenied);
    expect(provider.errorMessage, contains('not authorized'));
  });

  test('server connectivity failure blocks access', () async {
    final provider = FirebaseStartupProvider(
      backend: _FakeBackend(uid: 'owner-uid', role: 'owner', online: false),
    );

    await provider.checkStartup();

    expect(provider.state, FirebaseStartupState.offline);
    expect(provider.errorMessage, contains('Internet connection'));
  });

  test('authentication errors return a clear message', () async {
    final provider = FirebaseStartupProvider(backend: _AuthErrorBackend());

    await provider.signIn('owner@example.com', 'bad-password');

    expect(provider.state, FirebaseStartupState.unauthenticated);
    expect(provider.errorMessage, 'Email or password is incorrect.');
  });
}

class _AuthErrorBackend extends _FakeBackend {
  @override
  Future<String?> signIn(String email, String password) async {
    throw FirebaseAuthException(code: 'invalid-credential');
  }
}
