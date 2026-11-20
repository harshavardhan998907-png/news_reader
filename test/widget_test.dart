import 'package:flutter_test/flutter_test.dart';

import 'package:news_reader/main.dart';

void main() {
  testWidgets('NewsReaderApp displays error screen when Firebase fails to initialize', (WidgetTester tester) async {
    await tester.pumpWidget(const NewsReaderApp(
      isFirebaseInitialized: false,
      initializationError: 'Test error message',
    ));

    expect(find.text('Firebase Initialization Failed'), findsOneWidget);
    expect(find.text('Test error message'), findsOneWidget);
  });
}
