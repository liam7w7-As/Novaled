import 'package:flutter_test/flutter_test.dart';
import 'package:panel_novaled/main.dart';

void main() {
  testWidgets('Smoke test panel novaled', (WidgetTester tester) async {
    await tester.pumpWidget(const PanelNovaledApp());
  });
}
