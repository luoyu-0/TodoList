import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/local/app_database.dart';
import 'reminder_time.dart';

class TodoNotificationService {
  TodoNotificationService._();

  static final instance = TodoNotificationService._();

  static const _summaryId = 1;
  static const _summaryChannelId = 'todo_summary';
  static const _androidChannel = MethodChannel('com.todolist/alarm');

  final _plugin = FlutterLocalNotificationsPlugin();
  static const _windowsChannel = MethodChannel('com.todolist/reminder');
  final Map<String, Timer> _windowsTimers = {};
  Future<void> _syncQueue = Future<void>.value();
  bool _initialized = false;

  Future<void> testAndroidAlarm() => _androidChannel.invokeMethod<void>('test');

  Future<String> androidAlarmStatus() async =>
      await _androidChannel.invokeMethod<String>('status') ?? '暂无诊断信息';

  Future<void> initialize() async {
    if ((!Platform.isAndroid && !Platform.isWindows) || _initialized) return;
    if (Platform.isWindows) {
      _initialized = true;
      return;
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (_) {},
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    _initialized = true;
  }

  Future<void> syncTasks(Iterable<Task> tasks, AppDatabase database) {
    if ((!Platform.isAndroid && !Platform.isWindows) || !_initialized) {
      return Future<void>.value();
    }
    final snapshot = tasks.toList(growable: false);
    _syncQueue = _syncQueue
        .catchError((Object error) {
          stderr.writeln('提醒同步失败：$error');
        })
        .then((_) => _syncTasks(snapshot, database));
    return _syncQueue;
  }

  Future<void> _syncTasks(List<Task> tasks, AppDatabase database) async {
    final activeTasks = tasks.where((task) => !task.completed).toList();
    final taskById = {for (final task in activeTasks) task.id: task};
    final extras = await database.getAdditionalReminders(taskById.keys);
    final alarms = <({String id, String taskId, String title, DateTime at})>[];
    for (final task in activeTasks) {
      if (!task.reminderEnabled) continue;
      final at = effectiveReminderAt(
        task.dueAt,
        task.dueHasTime,
        task.reminderAt,
      );
      if (at != null && at.isAfter(DateTime.now())) {
        alarms.add((id: task.id, taskId: task.id, title: task.title, at: at));
      }
    }
    for (final extra in extras) {
      final task = taskById[extra.taskId];
      if (task != null &&
          task.reminderEnabled &&
          task.dueAt != null &&
          extra.remindAt.isAfter(DateTime.now())) {
        alarms.add((id: extra.id, taskId: task.id, title: task.title, at: extra.remindAt));
      }
    }
    if (Platform.isWindows) {
      for (final timer in _windowsTimers.values) {
        timer.cancel();
      }
      _windowsTimers.clear();
      for (final alarm in alarms) {
        final delay = alarm.at.difference(DateTime.now());
        if (delay <= Duration.zero) continue;
        _windowsTimers[alarm.id] = Timer(delay, () async {
          _windowsTimers.remove(alarm.id);
          try {
            await _windowsChannel.invokeMethod<void>('show', {
              'title': alarm.title,
            });
          } catch (error) {
            stderr.writeln('Windows 提醒弹窗失败：$error');
          }
        });
      }
      return;
    }
    if (Platform.isAndroid) {
      await _updateSummary(activeTasks);
      final pending = await _plugin.pendingNotificationRequests();
      for (final notification in pending) {
        if (notification.id != _summaryId) {
          await _plugin.cancel(id: notification.id);
        }
      }
      await _androidChannel.invokeMethod<void>('sync', {
        'alarms': alarms.map((alarm) {
          return {
            'id': _taskNotificationId(alarm.id),
            'taskId': alarm.taskId,
            'title': alarm.title,
            'at': alarm.at.millisecondsSinceEpoch,
          };
        }).toList(),
      });
      return;
    }
  }

  Future<void> _updateSummary(List<Task> tasks) async {
    if (tasks.isEmpty) {
      await _plugin.cancel(id: _summaryId);
      return;
    }
    final titles = tasks.take(5).map((task) => task.title).join('、');
    final body = tasks.length > 5 ? '$titles 等 ${tasks.length} 项待办' : titles;
    await _plugin.show(
      id: _summaryId,
      title: 'TodoList · ${tasks.length} 个待办',
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _summaryChannelId,
          '待办汇总',
          channelDescription: '显示未完成待办任务的汇总信息',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          playSound: false,
          enableVibration: false,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
    );
  }

  int _taskNotificationId(String taskId) {
    var hash = 2166136261;
    for (final codeUnit in taskId.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return 1000 + hash % 2000000000;
  }
}
