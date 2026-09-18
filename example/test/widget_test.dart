import 'package:flutter_test/flutter_test.dart';
import 'package:zero_tap_easy_example/main.dart';

void main() {
  testWidgets('renders and reports that restore keys are unsupported in a test',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ZeroTapDemoApp());
    await tester.pumpAndSettle();

    // There is no Android implementation behind a widget test, so the demo
    // should degrade to the unsupported state rather than blow up.
    expect(
      find.text('Restore keys not supported on this device'),
      findsOneWidget,
    );
    expect(find.text('Create'), findsOneWidget);
  });
}
