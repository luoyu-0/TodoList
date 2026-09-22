import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:drift/native.dart';

part 'app_database.g.dart';

class TaskLists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get sortMode => text().withDefault(const Constant('createdAt'))();
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

@DriftDatabase(tables: [TaskLists, Tasks, TaskAttachments])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.test() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 3;

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
        },
      );

  Stream<List<Task>> watchInbox() {
    final query = select(tasks)
      ..where((task) => task.deletedAt.isNull())
      ..orderBy([
        (task) => OrderingTerm(expression: task.completed),
        (task) => OrderingTerm(
              expression: task.createdAt,
              mode: OrderingMode.desc,
            ),
      ]);
    return query.watch();
  }

  Future<void> ensureDefaultList() async {
    await purgeExpiredTrash();
    final existing = await (select(taskLists)..limit(1)).getSingleOrNull();
    if (existing != null) return;
    await into(taskLists).insert(
      TaskListsCompanion.insert(id: 'inbox', name: '收件箱'),
    );
  }

  Future<String> getSortMode() async {
    final list = await (select(taskLists)
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

  Future<void> addTask({
    required String title,
    String? note,
    String? parentTaskId,
    int priority = 0,
    DateTime? dueAt,
  }) async {
    final lastTask = await (select(tasks)
          ..where((task) => task.deletedAt.isNull())
          ..orderBy([
            (task) => OrderingTerm(
                  expression: task.sortOrder,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(1))
        .getSingleOrNull();
    await into(tasks).insert(
      TasksCompanion.insert(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        listId: 'inbox',
        title: title,
        note: Value(note),
        parentTaskId: Value(parentTaskId),
        priority: Value(priority),
        sortOrder: Value((lastTask?.sortOrder ?? -1) + 1),
        dueAt: Value(dueAt),
      ),
    );
  }

  Future<void> setTaskCompleted(String id, bool completed) {
    return (update(tasks)..where((task) => task.id.equals(id))).write(
      TasksCompanion(
        completed: Value(completed),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateTask({
    required String id,
    required String title,
    String? note,
    DateTime? dueAt,
  }) {
    return (update(tasks)..where((task) => task.id.equals(id))).write(
      TasksCompanion(
        title: Value(title),
        note: Value(note),
        dueAt: Value(dueAt),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateTaskOrder(List<String> taskIds) async {
    await transaction(() async {
      for (var index = 0; index < taskIds.length; index++) {
        await (update(tasks)..where((task) => task.id.equals(taskIds[index])))
            .write(
          TasksCompanion(
            sortOrder: Value(index),
          ),
        );
      }
    });
  }

  Future<void> softDeleteTask(String id) {
    return (update(tasks)..where((task) => task.id.equals(id))).write(
      TasksCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Stream<List<Task>> watchTrash() {
    final query = select(tasks)
      ..where((task) => task.deletedAt.isNotNull())
      ..orderBy([
        (task) => OrderingTerm(
              expression: task.deletedAt,
              mode: OrderingMode.desc,
            ),
      ]);
    return query.watch();
  }

  Future<void> restoreTask(String id) {
    return (update(tasks)..where((task) => task.id.equals(id))).write(
      TasksCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> permanentlyDeleteTask(String id) {
    return (delete(tasks)..where((task) => task.id.equals(id))).go();
  }

  Future<void> purgeExpiredTrash() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final expired = await (select(tasks)
          ..where(
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
      for (final id in taskIds) {
        await (delete(taskAttachments)
              ..where((attachment) => attachment.taskId.equals(id)))
            .go();
        await (delete(tasks)..where((task) => task.id.equals(id))).go();
      }
    });
  }
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'todolist');
}
