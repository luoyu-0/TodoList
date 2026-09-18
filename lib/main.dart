import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'data/local/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    const options = WindowOptions(
      size: Size(1024, 720),
      minimumSize: Size(360, 120),
      center: true,
      title: 'TodoList',
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final database = AppDatabase();
  await database.ensureDefaultList();
  runApp(TodoListApp(database: database));
}

class TodoListApp extends StatelessWidget {
  const TodoListApp({required this.database, super.key});

  final AppDatabase database;

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
      home: TodoHomePage(database: database),
    );
  }
}

class TodoHomePage extends StatefulWidget {
  const TodoHomePage({required this.database, super.key});

  final AppDatabase database;

  @override
  State<TodoHomePage> createState() => _TodoHomePageState();
}

class _TodoHomePageState extends State<TodoHomePage> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isPinned = false;
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    _loadWindowState();
  }

  Future<void> _loadWindowState() async {
    if (Platform.isWindows) {
      final maximized = await windowManager.isMaximized();
      if (mounted) setState(() => _isMaximized = maximized);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    widget.database.close();
    super.dispose();
  }

  Future<void> _showTaskEditor({Task? task}) async {
    _titleController.text = task?.title ?? '';
    _noteController.text = task?.note ?? '';
    DateTime? selectedDueAt = task?.dueAt;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(task == null ? '新增任务' : '任务详情'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _titleController,
                    autofocus: true,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: '标题',
                      hintText: '输入任务内容',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteController,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: '描述/备注（可选）',
                      hintText: '补充任务说明',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedDueAt == null
                              ? '截止日期：未设置'
                              : '截止日期：' + _formatDate(selectedDueAt!),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2100),
                            initialDate: selectedDueAt != null &&
                                    selectedDueAt!.isBefore(DateTime.now())
                                ? DateTime.now()
                                : selectedDueAt ?? DateTime.now(),
                          );
                          if (date != null) {
                            setDialogState(() => selectedDueAt = date);
                          }
                        },
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: const Text('选择日期'),
                      ),
                      if (selectedDueAt != null)
                        IconButton(
                          onPressed: () =>
                              setDialogState(() => selectedDueAt = null),
                          icon: const Icon(Icons.clear),
                          tooltip: '清除日期',
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final title = _titleController.text.trim();
                if (title.isEmpty) return;
                final note = _noteController.text.trim();
                if (task == null) {
                  await widget.database.addTask(
                    title: title,
                    note: note.isEmpty ? null : note,
                    dueAt: selectedDueAt,
                  );
                } else {
                  await widget.database.updateTask(
                    id: task.id,
                    title: title,
                    note: note.isEmpty ? null : note,
                    dueAt: selectedDueAt,
                  );
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: Text(task == null ? '添加' : '保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTaskMenu(Task task, Offset position) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        MediaQuery.of(context).size.width - position.dx,
        MediaQuery.of(context).size.height - position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'edit', child: Text('查看详情 / 编辑')),
        PopupMenuItem(value: 'delete', child: Text('移入回收站')),
      ],
    );
    if (!mounted) return;
    if (selected == 'edit') {
      await _showTaskEditor(task: task);
    } else if (selected == 'delete') {
      await widget.database.softDeleteTask(task.id);
    }
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return date.year.toString() + '-' + month + '-' + day;
  }

  Widget? _buildTaskSubtitle(Task task) {
    final details = <String>[];
    if (task.note != null && task.note!.trim().isNotEmpty) {
      details.add(task.note!.trim());
    }
    if (task.dueAt != null) {
      details.add('截止：' + _formatDate(task.dueAt!));
    }
    if (details.isEmpty) return null;
    return Text(
      details.join('  ·  '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Future<void> _togglePinned() async {
    if (!Platform.isWindows) return;
    if (_isPinned) {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setResizable(true);
      await windowManager.setSize(const Size(1024, 720));
      await windowManager.center();
    } else {
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setResizable(false);
      await windowManager.setSize(const Size(420, 120));
      await windowManager.setPosition(const Offset(64, 120));
    }
    if (mounted) setState(() => _isPinned = !_isPinned);
  }

  Future<void> _toggleMaximized() async {
    if (!Platform.isWindows) return;
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
      if (mounted) setState(() => _isMaximized = false);
    } else {
      await windowManager.maximize();
      if (mounted) setState(() => _isMaximized = true);
    }
  }

  Future<void> _minimizeWindow() async {
    if (Platform.isWindows) await windowManager.minimize();
  }

  Future<void> _closeWindow() async {
    if (Platform.isWindows) await windowManager.close();
  }

  Widget _buildWindowTitleBar() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) {
        if (Platform.isWindows) windowManager.startDragging();
      },
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 18),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'TodoList',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              onPressed: _togglePinned,
              icon: const Icon(Icons.push_pin_outlined, size: 18),
              tooltip: '固定到桌面',
            ),
            if (Platform.isWindows) ...[
              _WindowControlButton(
                icon: Icons.remove,
                tooltip: '最小化',
                onPressed: _minimizeWindow,
              ),
              _WindowControlButton(
                icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
                tooltip: _isMaximized ? '还原' : '最大化',
                onPressed: _toggleMaximized,
              ),
              _WindowControlButton(
                icon: Icons.close,
                tooltip: '退出',
                onPressed: _closeWindow,
                isClose: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isPinned) return _buildPinnedBar();
    return _buildMainPage();
  }

  Widget _buildPinnedBar() {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: StreamBuilder<List<Task>>(
          stream: widget.database.watchInbox(),
          builder: (context, snapshot) {
            final tasks = snapshot.data ?? const <Task>[];
            final pending = tasks.where((task) => !task.completed).toList();
            final task = pending.isEmpty ? null : pending.first;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _togglePinned,
                    icon: const Icon(Icons.push_pin),
                    tooltip: '取消桌面悬浮',
                  ),
                  Expanded(
                    child: Text(
                      task?.title ?? '暂无待办',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (task != null)
                    Checkbox(
                      value: task.completed,
                      onChanged: (value) => widget.database.setTaskCompleted(
                        task.id,
                        value ?? false,
                      ),
                    ),
                  IconButton(
                    onPressed: () => _showTaskEditor(),
                    icon: const Icon(Icons.add),
                    tooltip: '新增任务',
                  ),
                  IconButton(
                    onPressed: _minimizeWindow,
                    icon: const Icon(Icons.remove),
                    tooltip: '最小化',
                  ),
                  IconButton(
                    onPressed: _closeWindow,
                    icon: const Icon(Icons.close),
                    tooltip: '退出',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMainPage() {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: _buildWindowTitleBar(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showTaskEditor(),
        icon: const Icon(Icons.add),
        label: const Text('新增任务'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: StreamBuilder<List<Task>>(
              stream: widget.database.watchInbox(),
              builder: (context, snapshot) {
                final tasks = snapshot.data ?? const <Task>[];
                final pending = tasks.where((task) => !task.completed).length;
                return Column(
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
                      child: tasks.isEmpty
                          ? const Center(child: Text('暂无待办，点击右下角新增任务'))
                          : ListView.separated(
                              itemCount: tasks.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final task = tasks[index];
                                return GestureDetector(
                                  onSecondaryTapDown: (details) =>
                                      _showTaskMenu(task, details.globalPosition),
                                  onLongPress: () => _showTaskEditor(task: task),
                                  child: Card(
                                    elevation: 0,
                                    child: CheckboxListTile(
                                      value: task.completed,
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      title: Text(
                                        task.title,
                                        style: TextStyle(
                                          decoration: task.completed
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                      subtitle: _buildTaskSubtitle(task),
                                      onChanged: (value) =>
                                          widget.database.setTaskCompleted(
                                        task.id,
                                        value ?? false,
                                      ),
                                      secondary: IconButton(
                                        onPressed: () => widget.database
                                            .softDeleteTask(task.id),
                                        icon:
                                            const Icon(Icons.delete_outline),
                                        tooltip: '移入回收站',
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowControlButton extends StatelessWidget {
  const _WindowControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 44,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 17),
        style: IconButton.styleFrom(
          shape: const RoundedRectangleBorder(),
          foregroundColor: isClose ? Colors.red.shade700 : null,
        ),
      ),
    );
  }
}
