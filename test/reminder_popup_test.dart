import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todolist/reminder_popup.dart';

void main() {
  testWidgets('提醒卡片显示、关闭和重新展示，并可打开主窗口', (tester) async {
    tester.view.physicalSize = const Size(400, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      reminderWindowChannel,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    await tester.pumpWidget(const ReminderPopupApp());
    expect(calls, contains('ready'));
    Future<void> show(String title) async {
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        reminderWindowChannel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall('show', title)),
        (_) {},
      );
      await tester.pump();
      await tester.pumpAndSettle();
    }

    await show('准备会议材料');
    expect(find.text('准备会议材料'), findsOneWidget);
    expect(calls, contains('present'));
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(calls, contains('dismiss'));
    await show('第二条提醒');
    expect(find.text('第二条提醒'), findsOneWidget);
    await tester.tap(find.text('打开 TodoList'));
    await tester.pumpAndSettle();
    expect(calls, contains('open'));
    await show('自动关闭检查');
    await tester.pump(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call == 'dismiss').length, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
