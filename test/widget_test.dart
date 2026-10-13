import 'package:flutter_test/flutter_test.dart';
import 'package:inv_management/main.dart';

void main() {
  testWidgets('setup page renders the inventory app heading', (tester) async {
    await tester.pumpWidget(const SetupPage());

    expect(find.text('إدارة المخازن والمبيعات'), findsOneWidget);
  });
}