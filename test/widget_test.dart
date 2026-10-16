import 'package:flutter/foundation.dart';
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

  testWidgets('展开任务后可新增并显示子任务', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.test();
    await database.ensureDefaultList();
    await database.addTask(title: '主任务');
    await tester.pumpWidget(TodoListApp(database: database));
    await tester.pumpAndSettle();

    expect(find.text('主任务'), findsOneWidget);
    expect(find.byTooltip('展开子任务'), findsNothing);
    await tester.tap(find.text('主任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增子任务'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '子任务');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('子任务'), findsOneWidget);
    final tasks = await tester.runAsync(() => database.watchInbox().first);
    final root = tasks!.singleWhere((task) => task.title == '主任务');
    final child = tasks.singleWhere((task) => task.title == '子任务');
    expect(child.parentTaskId, root.id);
    expect(find.byTooltip('收起子任务'), findsOneWidget);
    expect(find.text('新增子任务'), findsNothing);
    await tester.tap(find.text('子任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增子任务'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '孙任务');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('孙任务'), findsOneWidget);
    final allTasks = await tester.runAsync(() => database.watchInbox().first);
    expect(
      allTasks!.singleWhere((task) => task.title == '孙任务').parentTaskId,
      child.id,
    );
    await tester.tap(find.text('孙任务'));
    await tester.pumpAndSettle();
    expect(find.text('新增子任务'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(
      (await tester.runAsync(() => database.watchInbox().first))!
          .every((task) => task.completed),
      isTrue,
    );
    expect(find.text('任务详情'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
  });

  testWidgets('个性化设置可从标题栏打开并保存展开偏好', (tester) async {
    tester.view.physicalSize = const Size(260, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.test();
    await database.ensureDefaultList();
    await tester.pumpWidget(TodoListApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('个性化设置'));
    await tester.pumpAndSettle();
    expect(find.text('默认展开子任务'), findsOneWidget);
    await tester.tap(find.text('默认展开子任务'));
    await tester.pumpAndSettle();
    expect((await database.getDisplaySettings()).expandSubtasks, isTrue);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
  });

  testWidgets('同级子任务可通过拖动手柄排序', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final database = AppDatabase.test();
    await database.ensureDefaultList();
    await database.addTask(title: '主任务');
    final root = (await tester.runAsync(() => database.watchInbox().first))!
        .single;
    await database.addTask(title: '子任务甲', parentTaskId: root.id);
    await database.addTask(title: '子任务乙', parentTaskId: root.id);
    await tester.pumpWidget(TodoListApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('展开子任务'));
    await tester.pumpAndSettle();

    final beforeA = tester.getTopLeft(find.text('子任务甲')).dy;
    final beforeB = tester.getTopLeft(find.text('子任务乙')).dy;
    final lowerTitle = beforeA > beforeB ? '子任务甲' : '子任务乙';
    final upperTitle = beforeA > beforeB ? '子任务乙' : '子任务甲';
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.drag_handle).last),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveBy(const Offset(0, -70));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester.getTopLeft(find.text(lowerTitle)).dy,
      lessThan(tester.getTopLeft(find.text(upperTitle)).dy),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(() => database.close());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('安卓任务行隐藏拖动手柄，标题支持两行并可长按拖动', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.test();
    await database.ensureDefaultList();
    const firstTitle = '这是一条比较长的任务标题需要显示两行内容';
    await database.addTask(title: firstTitle);
    await tester.pump(const Duration(milliseconds: 1));
    await database.addTask(title: '第二任务');
    await tester.pumpWidget(TodoListApp(database: database));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.drag_handle), findsNothing);
    expect(tester.widget<Text>(find.text(firstTitle)).maxLines, 2);
    final firstY = tester.getTopLeft(find.text(firstTitle)).dy;
    final secondY = tester.getTopLeft(find.text('第二任务')).dy;
    final lowerTitle = firstY > secondY ? firstTitle : '第二任务';
    final upperTitle = firstY > secondY ? '第二任务' : firstTitle;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text(lowerTitle)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text(lowerTitle)).dy,
      lessThan(tester.getTopLeft(find.text(upperTitle)).dy),
    );
    expect(find.text('任务详情'), findsNothing);
    await tester.tap(find.text(firstTitle));
    await tester.pumpAndSettle();
    expect(find.text('任务详情'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(() => database.close());
  });

  testWidgets('极窄窗口中多层任务行不溢出', (tester) async {
    tester.view.physicalSize = const Size(260, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.test();
    await database.ensureDefaultList();
    await database.setDisplaySettings(expandSubtasks: true);
    await database.addTask(title: '主任务');
    final root = (await tester.runAsync(() => database.watchInbox().first))!
        .single;
    await database.addTask(title: '子任务', parentTaskId: root.id);
    final child = (await tester.runAsync(() => database.watchInbox().first))!
        .singleWhere((task) => task.title == '子任务');
    await database.addTask(title: '孙任务', parentTaskId: child.id);
    await tester.pumpWidget(TodoListApp(database: database));
    await tester.pumpAndSettle();
    expect(find.text('孙任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(() => database.close());
  });
}
