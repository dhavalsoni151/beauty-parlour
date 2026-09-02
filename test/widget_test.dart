import 'package:flutter_test/flutter_test.dart';
import 'package:beauty_parlour/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const BeautyParlourApp());
    expect(find.byType(BeautyParlourApp), findsOneWidget);
  });
}
