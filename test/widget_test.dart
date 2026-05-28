// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_power_view/main.dart';
import 'package:app_power_view/src/ui/monitor_page.dart';
import 'package:app_power_view/src/services/device_client.dart';

void main() {
  testWidgets('PowerView config app smoke test', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(const PowerViewApp());
    await tester.pumpAndSettle();

    expect(find.text('PowerView Manager'), findsOneWidget);
    expect(find.text('Connect via TCP'), findsOneWidget);
  });

  testWidgets('PowerView config app renders on portrait mobile',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(const PowerViewApp());
    await tester.pumpAndSettle();

    expect(find.text('PowerView Manager'), findsOneWidget);
    expect(find.text('Connect via TCP'), findsOneWidget);
  });

  testWidgets('embedded dashboard fills portrait mobile viewport',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.expand(
          child: MonitorPage(
            host: '127.0.0.1',
            embedded: true,
            enablePolling: false,
            client: DeviceClient(),
          ),
        ),
      ),
    );
    await tester.pump();

    final stack = tester.widget<Stack>(find.byType(Stack).first);
    expect(stack.fit, StackFit.expand);
    expect(find.textContaining('Connecting to Pi display'), findsOneWidget);
  });
}
