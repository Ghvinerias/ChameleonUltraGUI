import 'package:chameleonultragui/wear/widgets/edge_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpIt(WidgetTester tester, {double? value}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Positioned.fill(
                child: EdgeProgress(value: value, animate: false),
              ),
              const Center(child: Text('content')),
            ],
          ),
        ),
      );

  testWidgets('draws determinate progress and keeps the content', (
    tester,
  ) async {
    await pumpIt(tester, value: 0.4);
    expect(find.byType(EdgeProgress), findsOneWidget);
    expect(find.text('content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not intercept taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox(width: 50, height: 50),
              ),
            ),
            const Positioned.fill(
              child: EdgeProgress(value: 0.5, animate: false),
            ),
          ],
        ),
      ),
    );
    await tester.tapAt(tester.getCenter(find.byType(GestureDetector)));
    expect(taps, 1);
  });

  testWidgets('indeterminate and out-of-range values do not throw', (
    tester,
  ) async {
    await pumpIt(tester);
    await pumpIt(tester, value: 7);
    await pumpIt(tester, value: -1);
    expect(tester.takeException(), isNull);
  });
}
