// 无数据库的提醒窗口检查入口：flutter run -d windows -t tool/reminder_preview.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:todolist/reminder_popup.dart';

@pragma('vm:entry-point')
void reminderMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReminderPopupApp());
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const channel = MethodChannel('com.todolist/reminder');
  channel.setMethodCallHandler((call) async {
    if (call.method == 'open') {
      await windowManager.show();
      await windowManager.focus();
    }
  });
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              await windowManager.hide();
              await channel.invokeMethod<void>('show', {
                'title': '准备会议材料 · 今天的任务已到提醒时间',
              });
              await channel.invokeMethod<void>('show', {
                'title': '第二条提醒：验证窗口复用和连续提醒',
              });
            },
            child: const Text('隐藏主窗口并测试两条提醒'),
          ),
        ),
      ),
    ),
  );
}
