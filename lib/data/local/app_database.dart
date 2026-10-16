import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:drift/native.dart';

part 'app_database.g.dart';

class TaskLists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get sortMode => text().withDefault(const Constant('createdAt'))();
  BoolColumn get sortAscending =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get expandSubtasks =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get showSubtasksInPin =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get listId => text().references(TaskLists, #id)();
  TextColumn get parentTaskId => text().nullable()();
  TextColumn get title => text().withLength(min: 1, max: 500)();
  TextColumn get note => text().nullable()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get dueAt => dateTime().nullable()();
  BoolColumn get dueHasTime => boolean().withDefault(const Constant(false))();
  DateTimeColumn get reminderAt => dateTime().nullable()();
  BoolColumn get reminderEnabled =>
      boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class TaskAttachments extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text().references(Tasks, #id)();
  TextColumn get fileName => text().withLength(min: 1, max: 255)();
  TextColumn get mimeType => text().withLength(min: 1, max: 100)();
  IntColumn get sizeBytes => integer()();
  TextColumn get localPath => text()();
  TextColumn get remotePath => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class TaskReminders extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text().references(Tasks, #id)();
  DateTimeColumn get remindAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [TaskLists, Tasks, TaskAttachments, TaskReminders])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.test() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) => m.createAll(),
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.addColumn(tasks, tasks.sortOrder);
      }
      if (from < 3) {
        await m.addColumn(taskLists, taskLists.sortMode);
      }
      if (from < 4) {
        await m.addColumn(taskLists, taskLists.sortAscending);
      }
      if (from < 5) {
        await m.addColumn(tasks, tasks.dueHasTime);
        await m.addColumn(tasks, tasks.reminderAt);
        await customStatement(
          'UPDATE tasks SET due_has_time = 1 WHERE due_at IS NOT NULL',
        );
      }
      if (from < 6) {
        await m.createTable(taskReminders);
      }
      if (from < 7) {
        await m.addColumn(tasks, tasks.reminderEnabled);
      }
      if (from < 8) {
        await m.addColumn(taskLists, taskLists.expandSubtasks);
        await m.addColumn(taskLists, taskLists.showSubtasksInPin);
      }
    },
  );

  Stream<List<Task>> watchInbox() {
    final query = select(tasks)..where((task) => task.deletedAt.isNull());
    return query.watch();
  }

  Future<void> ensureDefaultList() async {
    await purgeExpiredTrash();
    final existing = await (select(taskLists)..limit(1)).getSingleOrNull();
    if (existing != null) return;
    await into(taskLists)
        .insert(TaskListsCompanion.insert(id: 'inbox', name: '收件箱'));
  }

  Future<String> getSortMode() async {
    final list =
        await (select(taskLists)
              ..where((item) => item.id.equals('inbox'))
              ..limit(1))
            .getSingleOrNull();
    return list?.sortMode ?? 'createdAt';
  }

  Future<void> setSortMode(String sortMode) {
    return (update(taskLists)..where((item) => item.id.equals('inbox'))).write(
      TaskListsCompanion(sortMode: Value(sortMode)),
    );
  }

  Future<bool> getSortAscending() async {
    final list =
        await (select(taskLists)
              ..where((item) => item.id.equals('inbox'))
              ..limit(1))
            .getSingleOrNull();
    return list?.sortAscending ?? false;
  }

  Future<void> setSortAscending(bool ascending) {
    return (update(taskLists)..where((item) => item.id.equals('inbox'))).write(
      TaskListsCompanion(sortAscending: Value(ascending)),
    );
  }

  Future<({bool expandSubtasks, bool showSubtasksInPin})>
  getDisplaySettings() async {
    final list =
        await (select(taskLists)
              ..where((item) => item.id.equals('inbox'))
              ..limit(1))
            .getSingleOrNull();
    return (
      expandSubtasks: list?.expandSubtasks ?? false,
      showSubtasksInPin: list?.showSubtasksInPin ?? false,
    );
  }

  Future<void> setDisplaySettings({
    bool? expandSubtasks,
    bool? showSubtasksInPin,
  }) {
    return (update(taskLists)..where((item) => item.id.equals('inbox'))).write(
      TaskListsCompanion(
        expandSubtasks: expandSubtasks == null
            ? const Value.absent()
            : Value(expandSubtasks),
        showSubtasksInPin: showSubtasksInPin == null
            ? const Value.absent()
            : Value(showSubtasksInPin),
      ),
    );
  }

  Future<void> addTask({
    required String title,
    String? note,
    String? parentTaskId,
    int priority = 0,
    DateTime? dueAt,
    bool dueHasTime = false,
    DateTime? reminderAt,
    bool reminderEnabled = true,
    List<DateTime> additionalReminders = const [],
  }) async {
    if (parentTaskId != null) {
      if (await getTaskDepth(parentTaskId) >= 3) {
        throw StateError('最多支持三层任务');
      }
    }
    final lastTask =
        await (select(tasks)
              ..where((task) => task.deletedAt.isNull())
              ..orderBy([
                (task) => OrderingTerm(
                  expression: task.sortOrder,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await transaction(() async {
      await into(tasks).insert(
        TasksCompanion.insert(
          id: id,
          listId: 'inbox',
          title: title,
          note: Value(note),
          parentTaskId: Value(parentTaskId),
          priority: Value(priority),
          sortOrder: Value((lastTask?.sortOrder ?? -1) + 1),
          dueAt: Value(dueAt),
          dueHasTime: Value(dueHasTime),
          reminderAt: Value(reminderAt),
          reminderEnabled: Value(reminderEnabled),
        ),
      );
      await _replaceAdditionalReminders(id, additionalReminders);
    });
  }

  Future<int> getTaskDepth(String taskId) async {
    var depth = 0;
    String? currentId = taskId;
    final visited = <String>{};
    while (currentId != null) {
      final id = currentId;
      if (!visited.add(id)) throw StateError('任务层级存在循环');
      final current =
          await (select(tasks)
                ..where((task) => task.id.equals(id) & task.deletedAt.isNull())
                ..limit(1))
              .getSingleOrNull();
      if (current == null) throw StateError('父任务不存在或已删除');
      depth++;
      currentId = current.parentTaskId;
    }
    return depth;
  }

  Future<void> setTaskCompleted(String id, bool completed) async {
    await transaction(() async {
      final affected = await _taskAndDescendantIds(id);
      if (affected.isEmpty) return;
      await (update(tasks)..where((task) => task.id.isIn(affected))).write(
        TasksCompanion(
          completed: Value(completed),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  Future<void> updateTask({
    required String id,
    required String title,
    String? note,
    DateTime? dueAt,
    bool dueHasTime = false,
    DateTime? reminderAt,
    bool? reminderEnabled,
    List<DateTime> additionalReminders = const [],
  }) async {
    await transaction(() async {
      await (update(tasks)..where((task) => task.id.equals(id))).write(
        TasksCompanion(
          title: Value(title),
          note: Value(note),
          dueAt: Value(dueAt),
          dueHasTime: Value(dueHasTime),
          reminderAt: Value(reminderAt),
          reminderEnabled: reminderEnabled == null
              ? const Value.absent()
              : Value(reminderEnabled),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _replaceAdditionalReminders(id, additionalReminders);
    });
  }

  Future<void> _replaceAdditionalReminders(
    String taskId,
    List<DateTime> reminders,
  ) async {
    await (delete(
      taskReminders,
    )..where((item) => item.taskId.equals(taskId))).go();
    for (var index = 0; index < reminders.length; index++) {
      await into(taskReminders).insert(
        TaskRemindersCompanion.insert(
          id: '$taskId:$index',
          taskId: taskId,
          remindAt: reminders[index],
        ),
      );
    }
  }

  Future<List<TaskReminder>> getAdditionalReminders(Iterable<String> ids) {
    final taskIds = ids.toList();
    if (taskIds.isEmpty) return Future.value([]);
    return (select(taskReminders)
          ..where((item) => item.taskId.isIn(taskIds))
          ..orderBy([(item) => OrderingTerm(expression: item.remindAt)]))
        .get();
  }

  Future<void> updateTaskOrder(List<String> taskIds) async {
    await transaction(() async {
      for (var index = 0; index < taskIds.length; index++) {
        await (update(tasks)..where((task) => task.id.equals(taskIds[index])))
            .write(TasksCompanion(sortOrder: Value(index)));
      }
    });
  }

  Future<void> softDeleteTask(String id) async {
    await transaction(() async {
      final affected = await _taskAndDescendantIds(id);
      if (affected.isEmpty) return;
      final now = DateTime.now();
      await (update(tasks)..where((task) => task.id.isIn(affected))).write(
        TasksCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
    });
  }

  Stream<List<Task>> watchTrash() {
    final query = select(tasks)
      ..where((task) => task.deletedAt.isNotNull())
      ..orderBy([
        (task) =>
            OrderingTerm(expression: task.deletedAt, mode: OrderingMode.desc),
      ]);
    return query.watch();
  }

  Future<void> restoreTask(String id) async {
    await transaction(() async {
      final all = await select(tasks).get();
      final byId = {for (final task in all) task.id: task};
      final affected = _collectTaskIds(id, all);
      var parentId = byId[id]?.parentTaskId;
      while (parentId != null &&
          byId.containsKey(parentId) &&
          affected.add(parentId)) {
        parentId = byId[parentId]?.parentTaskId;
      }
      if (affected.isEmpty) return;
      await (update(tasks)..where((task) => task.id.isIn(affected))).write(
        TasksCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  Future<void> permanentlyDeleteTask(String id) {
    return permanentlyDeleteTasks([id]);
  }

  Future<void> purgeExpiredTrash() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final expired =
        await (select(tasks)..where(
              (task) =>
                  task.deletedAt.isNotNull() &
                  task.deletedAt.isSmallerThanValue(cutoff),
            ))
            .get();
    if (expired.isEmpty) return;
    await permanentlyDeleteTasks(expired.map((task) => task.id));
  }

  Future<void> permanentlyDeleteTasks(Iterable<String> ids) async {
    final taskIds = ids.toList();
    if (taskIds.isEmpty) return;
    await transaction(() async {
      final all = await select(tasks).get();
      final affected = <String>{};
      for (final id in taskIds) {
        affected.addAll(_collectTaskIds(id, all));
      }
      if (affected.isEmpty) return;
      await (delete(
        taskReminders,
      )..where((reminder) => reminder.taskId.isIn(affected))).go();
      await (delete(
        taskAttachments,
      )..where((attachment) => attachment.taskId.isIn(affected))).go();
      await (delete(tasks)..where((task) => task.id.isIn(affected))).go();
    });
  }

  Future<Set<String>> _taskAndDescendantIds(String id) async {
    return _collectTaskIds(id, await select(tasks).get());
  }

  Set<String> _collectTaskIds(String id, List<Task> all) {
    if (!all.any((task) => task.id == id)) return {};
    final children = <String, List<String>>{};
    for (final task in all) {
      if (task.parentTaskId != null) {
        children.putIfAbsent(task.parentTaskId!, () => []).add(task.id);
      }
    }
    final result = <String>{};
    final pending = <String>[id];
    while (pending.isNotEmpty) {
      final next = pending.removeLast();
      if (result.add(next)) pending.addAll(children[next] ?? const []);
    }
    return result;
  }
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'todolist');
}
