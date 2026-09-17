import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todolist/main.dart';

void main() {
  testWidgets('显示初始任务列表', (tester) async {
    await tester.pumpWidget(const TodoListApp());

    expect(find.text('TodoList'), findsOneWidget);
    expect(find.text('收件箱'), findsOneWidget);
    expect(find.text('熟悉 TodoList 项目结构'), findsOneWidget);
    expect(find.text('2 个待办'), findsOneWidget);
  });

  testWidgets('可以新增并完成任务', (tester) async {
    await tester.pumpWidget(const TodoListApp());

    await tester.tap(find.byTooltip('新增任务'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '完成 Flutter 环境配置');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(find.text('完成 Flutter 环境配置'), findsOneWidget);
    expect(find.text('3 个待办'), findsOneWidget);
  });
}
