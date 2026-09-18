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
    await database.close();
  });
}
