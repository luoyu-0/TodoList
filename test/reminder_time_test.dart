import 'package:flutter_test/flutter_test.dart';
import 'package:todolist/data/local/app_database.dart';
import 'package:todolist/services/reminder_time.dart';

void main() {
  test('24 小时时间输入只接受 HH:mm', () {
    final date = DateTime(2026, 10, 20);
    expect(with24HourTime(date, '23:59'), DateTime(2026, 10, 20, 23, 59));
    expect(with24HourTime(date, '00:00'), DateTime(2026, 10, 20));
    expect(with24HourTime(date, '24:00'), isNull);
    expect(with24HourTime(date, '9:30'), isNull);
    expect(with24HourTime(date, '12:60'), isNull);
  });

  test('全天任务默认在当天上午九点提醒，具体时间跟随截止时间', () {
    final dueAt = DateTime(2026, 10, 20);
    expect(effectiveReminderAt(dueAt, false, null), DateTime(2026, 10, 20, 9));
    final timedDueAt = DateTime(2026, 10, 20, 15, 30);
    expect(effectiveReminderAt(timedDueAt, true, null), timedDueAt);
    expect(
      effectiveReminderAt(timedDueAt, true, DateTime(2026, 10, 19, 8)),
      DateTime(2026, 10, 19, 8),
    );
  });

  test('截止时间与独立提醒时间保存后仍保持独立', () async {
    final database = AppDatabase.test();
    await database.ensureDefaultList();
    await database.addTask(
      title: '测试提醒',
      dueAt: DateTime(2026, 10, 20),
      reminderAt: DateTime(2026, 10, 19, 8),
    );
    final task = (await database.watchInbox().first).single;
    expect(task.dueHasTime, isFalse);
    expect(task.dueAt, DateTime(2026, 10, 20));
    expect(task.reminderAt, DateTime(2026, 10, 19, 8));
    expect(task.reminderEnabled, isTrue);
    await database.updateTask(
      id: task.id,
      title: task.title,
      dueAt: task.dueAt,
      reminderAt: task.reminderAt,
      reminderEnabled: false,
    );
    final disabled = (await database.watchInbox().first).single;
    expect(disabled.reminderEnabled, isFalse);
    expect(disabled.reminderAt, DateTime(2026, 10, 19, 8));
    await database.updateTask(
      id: task.id,
      title: task.title,
      dueAt: task.dueAt,
      reminderAt: disabled.reminderAt,
      reminderEnabled: true,
    );
    expect((await database.watchInbox().first).single.reminderEnabled, isTrue);
    await database.close();
  });

  test('一条任务可保存多个额外提醒并在编辑后替换', () async {
    final database = AppDatabase.test();
    await database.ensureDefaultList();
    final first = DateTime(2026, 10, 19, 8);
    final second = DateTime(2026, 10, 20, 7);
    await database.addTask(
      title: '多次提醒',
      dueAt: DateTime(2026, 10, 20),
      additionalReminders: [first, second],
    );
    final task = (await database.watchInbox().first).single;
    var reminders = await database.getAdditionalReminders([task.id]);
    expect(reminders.map((item) => item.remindAt), [first, second]);
    await database.updateTask(
      id: task.id,
      title: task.title,
      dueAt: task.dueAt,
      additionalReminders: [second],
    );
    reminders = await database.getAdditionalReminders([task.id]);
    expect(reminders.map((item) => item.remindAt), [second]);
    await database.permanentlyDeleteTask(task.id);
    expect(await database.getAdditionalReminders([task.id]), isEmpty);
    await database.close();
  });
}
