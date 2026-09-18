import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:drift/native.dart';

part 'app_database.g.dart';

class TaskLists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
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
  int get schemaVersion => 1;

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
    final existing = await (select(taskLists)..limit(1)).getSingleOrNull();
    if (existing != null) return;
    await into(taskLists).insert(
      TaskListsCompanion.insert(id: 'inbox', name: '收件箱'),
    );
  }

  Future<void> addTask({
    required String title,
    String? note,
    String? parentTaskId,
    int priority = 0,
    DateTime? dueAt,
  }) async {
    await into(tasks).insert(
      TasksCompanion.insert(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        listId: 'inbox',
        title: title,
        note: Value(note),
        parentTaskId: Value(parentTaskId),
        priority: Value(priority),
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

  Future<void> softDeleteTask(String id) {
    return (update(tasks)..where((task) => task.id.equals(id))).write(
      TasksCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'todolist');
}
