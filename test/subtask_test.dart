import 'package:flutter_test/flutter_test.dart';
import 'package:todolist/data/local/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.test();
    await database.ensureDefaultList();
  });

  tearDown(() async {
    await database.close();
  });

  Future<String> add(String title, {String? parentTaskId}) async {
    await database.addTask(title: title, parentTaskId: parentTaskId);
    final tasks = await database.watchInbox().first;
    return tasks.singleWhere((task) => task.title == title).id;
  }

  test('多层子任务保留父子关系与完整任务字段', () async {
    final root = await add('主任务');
    final child = await add('子任务', parentTaskId: root);
    final dueAt = DateTime(2027, 1, 2, 18, 30);
    await database.addTask(
      title: '孙任务',
      parentTaskId: child,
      note: '备注',
      dueAt: dueAt,
      dueHasTime: true,
      reminderAt: dueAt,
    );
    final grandchild = (await database.watchInbox().first).singleWhere(
      (task) => task.title == '孙任务',
    );
    expect(grandchild.parentTaskId, child);
    expect(grandchild.note, '备注');
    expect(grandchild.dueAt, dueAt);
    expect(grandchild.reminderAt, dueAt);
    expect(await database.getTaskDepth(root), 1);
    expect(await database.getTaskDepth(child), 2);
    expect(await database.getTaskDepth(grandchild.id), 3);
    await expectLater(
      database.addTask(title: '第四层任务', parentTaskId: grandchild.id),
      throwsStateError,
    );
    await expectLater(
      database.addTask(title: '无效子任务', parentTaskId: 'missing'),
      throwsStateError,
    );
  });

  test('勾选主任务递归更新后代，单独勾选子任务不改主任务', () async {
    final root = await add('主任务');
    final child = await add('子任务', parentTaskId: root);
    await add('孙任务', parentTaskId: child);
    await database.setTaskCompleted(root, true);
    expect(
      (await database.watchInbox().first).every((task) => task.completed),
      isTrue,
    );
    await database.setTaskCompleted(child, false);
    final tasks = {
      for (final task in await database.watchInbox().first) task.title: task,
    };
    expect(tasks['主任务']!.completed, isTrue);
    expect(tasks['子任务']!.completed, isFalse);
    expect(tasks['孙任务']!.completed, isFalse);
  });

  test('删除、恢复和永久删除主任务时递归处理后代', () async {
    final root = await add('主任务');
    final child = await add('子任务', parentTaskId: root);
    await add('孙任务', parentTaskId: child);
    await database.softDeleteTask(root);
    expect(await database.watchInbox().first, isEmpty);
    expect(await database.watchTrash().first, hasLength(3));
    await database.restoreTask(root);
    expect(await database.watchInbox().first, hasLength(3));
    await database.softDeleteTask(root);
    await database.permanentlyDeleteTask(root);
    expect(await database.watchTrash().first, isEmpty);
  });

  test('恢复子任务时会恢复其祖先，个性化设置可持久化', () async {
    final root = await add('主任务');
    final child = await add('子任务', parentTaskId: root);
    await database.softDeleteTask(root);
    await database.restoreTask(child);
    expect(await database.watchInbox().first, hasLength(2));
    await database.setDisplaySettings(
      expandSubtasks: true,
      showSubtasksInPin: true,
    );
    final settings = await database.getDisplaySettings();
    expect(settings.expandSubtasks, isTrue);
    expect(settings.showSubtasksInPin, isTrue);
  });
}
