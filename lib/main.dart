import 'package:flutter/material.dart';

void main() => runApp(const TodoListApp());

class TodoListApp extends StatelessWidget {
  const TodoListApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TodoList',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4F46E5)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),
      home: const TodoHomePage(),
    );
  }
}

class TodoItem {
  TodoItem(this.title, {this.completed = false});

  final String title;
  bool completed;
}

class TodoHomePage extends StatefulWidget {
  const TodoHomePage({super.key});

  @override
  State<TodoHomePage> createState() => _TodoHomePageState();
}

class _TodoHomePageState extends State<TodoHomePage> {
  final _controller = TextEditingController();
  final _tasks = <TodoItem>[
    TodoItem('熟悉 TodoList 项目结构'),
    TodoItem('确认本地数据存储方案'),
    TodoItem('准备 Android 测试设备', completed: true),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addTask() {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    setState(() {
      _tasks.insert(0, TodoItem(title));
      _controller.clear();
    });
  }

  Future<void> _showAddTaskDialog() async {
    _controller.clear();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增任务'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 200,
          decoration: const InputDecoration(
            hintText: '输入任务内容',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              _addTask();
              Navigator.pop(context);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _tasks.where((task) => !task.completed).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('TodoList'),
        actions: [
          IconButton(
            onPressed: _showAddTaskDialog,
            icon: const Icon(Icons.add),
            tooltip: '新增任务',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTaskDialog,
        icon: const Icon(Icons.add),
        label: const Text('新增任务'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '收件箱',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text('$pending 个待办'),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView.separated(
                    itemCount: _tasks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final task = _tasks[index];
                      return Card(
                        elevation: 0,
                        child: CheckboxListTile(
                          value: task.completed,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            task.title,
                            style: TextStyle(
                              decoration: task.completed
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          onChanged: (value) => setState(
                            () => task.completed = value ?? false,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
