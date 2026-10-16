import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todolist/data/local/app_database.dart';
import 'package:todolist/main.dart';

void main() {
  testWidgets('显示 TodoList 首页', (tester) async {
    final database = AppDatabase.test();
    await database.ensureDefaultList();
    await tester.pumpWidget(TodoListApp(database: database));
    await tester.pump();

    expect(find.text('TodoList'), findsOneWidget);
    expect(find.text('收件箱'), findsOneWidget);
    expect(find.text('0 个待办'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
  });

  testWidgets('窄屏选择全天截止日期后编辑器不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.test();
    await database.ensureDefaultList();
    await tester.pumpWidget(TodoListApp(database: database));
    await tester.pump();
    await tester.tap(find.text('新增任务'));
    await tester.pumpAndSettle();
    expect(find.text('跟随截止时间'), findsNothing);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入任务标题'), findsOneWidget);
    expect(find.text('测试闹钟'), findsNothing);
    await tester.tap(find.text('截止日期'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('选择日期'));
    await tester.tap(find.text('选择日期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    await tester.tap(find.text('截止日期'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('提醒 1'));
    await tester.tap(find.text('提醒 1'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('新增提醒时间'));
    await tester.tap(find.text('新增提醒时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('提醒 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byTooltip('删除提醒'));
    await tester.tap(find.byTooltip('删除提醒'));
    await tester.pumpAndSettle();
    expect(find.text('提醒 2'), findsNothing);
    await tester.ensureVisible(find.text('提醒'));
    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();
    expect(find.text('已关闭，提醒时间已保留'), findsOneWidget);
    expect(find.text('提醒 1'), findsNothing);
    await tester.ensureVisible(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, '正式任务');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final saved = (await tester.runAsync(() => database.watchInbox().first))!
        .single;
    expect(saved.title, '正式任务');
    expect(saved.dueAt, isNotNull);
    expect(saved.reminderAt, isNotNull);
    expect(saved.reminderEnabled, isFalse);
    expect(
      await tester.runAsync(() => database.getAdditionalReminders([saved.id])),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
  });
}
