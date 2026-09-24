import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:beauty_parlour/app.dart';
import 'package:beauty_parlour/core/providers/app_lock_provider.dart';
import 'package:beauty_parlour/core/providers/settings_provider.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => AppLockProvider()),
        ],
        child: const BeautyParlourApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(BeautyParlourApp), findsOneWidget);
  });
}
