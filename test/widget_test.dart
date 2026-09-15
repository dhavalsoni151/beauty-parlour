import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:beauty_parlour/app.dart';
import 'package:beauty_parlour/core/providers/app_lock_provider.dart';
import 'package:beauty_parlour/core/providers/firebase_startup_provider.dart';
import 'package:beauty_parlour/core/providers/settings_provider.dart';

class _UnauthenticatedBackend implements FirebaseStartupBackend {
  @override
  String? get currentUserUid => null;

  @override
  Future<String?> signIn(String email, String password) async => null;

  @override
  Future<String?> memberRole(String uid) async => null;

  @override
  Future<void> requireOnline() async {}

  @override
  Future<void> signOut() async {}
}

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) =>
                FirebaseStartupProvider(backend: _UnauthenticatedBackend()),
          ),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => AppLockProvider()),
        ],
        child: const BeautyParlourApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(BeautyParlourApp), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });
}
