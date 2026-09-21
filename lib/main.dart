import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import 'data/local/app_database.dart';

enum TaskSortMode {
  createdAt,
  title,
  dueAt,
  manual,
}

bool _isPinnedWindow = false;

class _TodoListTrayController {
  late final tray.TrayIcon _trayIcon;

  Future<void> initialize() async {
    _trayIcon = tray.TrayIcon.create()!;
    _trayIcon.icon = tray.ImageAsset.fromAsset('assets/todolist.ico');
    _trayIcon.setTooltip('TodoList');

    final menu = tray.Menu.create()!;
    final showWindowItem = tray.MenuItem.createWithLabelAndType(
      '打开 TodoList',
      tray.MenuItemType.normal,
    )!;
    showWindowItem.addListener((event) {
      if (event is tray.MenuItemClickedEvent) {
        _showWindow();
      }
    });
    final exitItem = tray.MenuItem.createWithLabelAndType(
      '退出 TodoList',
      tray.MenuItemType.normal,
    )!;
    exitItem.addListener((event) {
      if (event is tray.MenuItemClickedEvent) {
        _exitApplication();
      }
    });
    menu.addItem(showWindowItem);
    menu.addSeparator();
    menu.addItem(exitItem);
    _trayIcon.setContextMenu(menu);
    _trayIcon.setContextMenuTrigger(tray.ContextMenuTrigger.rightClicked);
    _trayIcon.addListener((event) {
      if (event is tray.TrayIconClickedEvent) {
        _showWindow();
      }
    });
    _trayIcon.setVisible(true);
  }

  void dispose() {
    _trayIcon.dispose();
  }

  Future<void> _showWindow() async {
    if (!_isPinnedWindow) {
      await windowManager.setSkipTaskbar(false);
    }
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  Future<void> _exitApplication() async {
    _trayIcon.dispose();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}

class _TodoListWindowListener extends WindowListener {
  @override
  Future<void> onWindowClose() async {
    if (await windowManager.isPreventClose()) {
      await windowManager.setSkipTaskbar(true);
      await windowManager.hide();
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    final trayController = _TodoListTrayController();
    await trayController.initialize();
    windowManager.addListener(_TodoListWindowListener());
    await windowManager.setPreventClose(true);
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    const options = WindowOptions(
      size: Size(1024, 720),
      minimumSize: Size(260, 120),
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
  bool _showTrash = false;
  TaskSortMode _sortMode = TaskSortMode.createdAt;
  final _selectedTrashIds = <String>{};
  final _pinnedHiddenTaskIds = <String>{};
  Offset? _lastPinnedPosition;
  Size? _lastPinnedSize;
  bool _lastPinnedAlwaysOnTop = true;
  Timer? _trashCleanupTimer;

  @override
  void initState() {
    super.initState();
    _loadWindowState();
    _trashCleanupTimer = Timer.periodic(
      const Duration(hours: 24),
      (_) => widget.database.purgeExpiredTrash(),
    );
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
    _trashCleanupTimer?.cancel();
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
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
                    decoration: InputDecoration(
                      labelText: '标题',
                      hintText: '输入任务内容',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteController,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 2000,
                    decoration: InputDecoration(
                      labelText: '描述/备注（可选）',
                      hintText: '补充任务说明',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
                              : '截止日期：${_formatDate(selectedDueAt!)}',
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
    return '${date.year}-$month-$day';
  }

  List<Task> _sortTasks(Iterable<Task> source) {
    final result = source.toList();
    result.sort((a, b) {
      if (a.completed != b.completed) {
        return a.completed ? 1 : -1;
      }
      switch (_sortMode) {
        case TaskSortMode.title:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case TaskSortMode.dueAt:
          if (a.dueAt == null && b.dueAt == null) return 0;
          if (a.dueAt == null) return 1;
          if (b.dueAt == null) return -1;
          return a.dueAt!.compareTo(b.dueAt!);
        case TaskSortMode.manual:
          return a.sortOrder.compareTo(b.sortOrder);
        case TaskSortMode.createdAt:
          return b.createdAt.compareTo(a.createdAt);
      }
    });
    return result;
  }

  String _sortModeLabel() {
    switch (_sortMode) {
      case TaskSortMode.createdAt:
        return '创建时间';
      case TaskSortMode.title:
        return '标题字典序';
      case TaskSortMode.dueAt:
        return '截止时间';
      case TaskSortMode.manual:
        return '手动排序';
    }
  }

  Future<void> _reorderTasks(List<Task> tasks, int oldIndex, int newIndex) async {
    final reordered = [...tasks];
    final task = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, task);
    setState(() => _sortMode = TaskSortMode.manual);
    await widget.database.updateTaskOrder(
      reordered.map((item) => item.id).toList(),
    );
  }

  Widget? _buildTaskSubtitle(Task task) {
    final hasNote = task.note != null && task.note!.trim().isNotEmpty;
    final hasDueDate = task.dueAt != null;
    if (!hasNote && !hasDueDate) return null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasNote)
          Text(
            task.note!.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        if (hasDueDate)
          Text(
            '截止：${_formatDate(task.dueAt!)}',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  Future<void> _togglePinned() async {
    if (!Platform.isWindows) return;
    if (_isPinned) {
      _lastPinnedPosition = await windowManager.getPosition();
      _lastPinnedSize = await windowManager.getSize();
      _lastPinnedAlwaysOnTop = await windowManager.isAlwaysOnTop();
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setResizable(true);
      await windowManager.setSkipTaskbar(false);
      await windowManager.setSize(const Size(1024, 720));
      await windowManager.center();
      _pinnedHiddenTaskIds.clear();
    } else {
      await windowManager.setAlwaysOnTop(_lastPinnedAlwaysOnTop);
      await windowManager.setResizable(true);
      await windowManager.setSkipTaskbar(false);
      await windowManager.setSize(_lastPinnedSize ?? const Size(260, 320));
      if (_lastPinnedPosition != null) {
        await windowManager.setPosition(_lastPinnedPosition!);
      } else {
        await windowManager.setPosition(const Offset(64, 120));
      }
    }
    _isPinnedWindow = !_isPinned;
    if (_isPinnedWindow) {
      await windowManager.setSkipTaskbar(true);
    }
    if (mounted) setState(() => _isPinned = _isPinnedWindow);
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

  void _toggleTrash() {
    setState(() {
      _showTrash = !_showTrash;
      _selectedTrashIds.clear();
    });
  }

  Future<void> _restoreSelected() async {
    for (final id in _selectedTrashIds) {
      await widget.database.restoreTask(id);
    }
    if (mounted) setState(() => _selectedTrashIds.clear());
  }

  Future<void> _confirmPermanentDelete(Iterable<String> ids) async {
    final taskIds = ids.toList();
    if (taskIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text('永久删除任务？'),
        content: Text(
          '将永久删除 ${taskIds.length} 个任务，删除后无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.database.permanentlyDeleteTasks(taskIds);
    if (mounted) setState(() => _selectedTrashIds.removeAll(taskIds));
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
              onPressed: _toggleTrash,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              tooltip: '回收站',
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
                tooltip: '隐藏到系统托盘',
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
    if (_showTrash) return _buildTrashPage();
    return _buildMainPage();
  }

  Widget _buildPinnedBar() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) {
        if (Platform.isWindows) windowManager.startDragging();
      },
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: StreamBuilder<List<Task>>(
            stream: widget.database.watchInbox(),
            builder: (context, snapshot) {
              final tasks = snapshot.data ?? const <Task>[];
            final visibleTasks = _sortTasks(
              tasks.where((task) => !_pinnedHiddenTaskIds.contains(task.id)),
            ).take(5).toList();
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'TodoList',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        onPressed: _minimizeWindow,
                        icon: const Icon(Icons.remove),
                        tooltip: '最小化',
                      ),
                      IconButton(
                        onPressed: _togglePinned,
                        icon: const Icon(Icons.push_pin),
                        tooltip: '取消固定',
                      ),
                    ],
                  ),
                  if (visibleTasks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('暂无待办'),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: visibleTasks.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final task = visibleTasks[index];
                          return CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: task.completed,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              task.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onChanged: (value) =>
                                widget.database.setTaskCompleted(
                              task.id,
                              value ?? false,
                            ),
                            secondary: IconButton(
                              onPressed: () => setState(
                                () => _pinnedHiddenTaskIds.add(task.id),
                              ),
                              icon: const Icon(Icons.visibility_off_outlined),
                              tooltip: '仅从本次悬浮中隐藏',
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTrashPage() {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: _buildWindowTitleBar(),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: StreamBuilder<List<Task>>(
              stream: widget.database.watchTrash(),
              builder: (context, snapshot) {
                final tasks = snapshot.data ?? const <Task>[];
                final selectedCount = _selectedTrashIds.length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '回收站',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (selectedCount > 0) ...[
                          TextButton.icon(
                            onPressed: _restoreSelected,
                            icon: const Icon(Icons.restore),
                            label: Text('恢复 $selectedCount'),
                          ),
                          FilledButton.icon(
                            onPressed: () =>
                                _confirmPermanentDelete(_selectedTrashIds),
                            icon: const Icon(Icons.delete_forever),
                            label: const Text('永久删除'),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('任务进入回收站后保留 30 天，之后会自动永久删除。'),
                    const SizedBox(height: 20),
                    Expanded(
                      child: tasks.isEmpty
                          ? const Center(child: Text('回收站为空'))
                          : ListView.separated(
                              itemCount: tasks.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final task = tasks[index];
                                final selected =
                                    _selectedTrashIds.contains(task.id);
                                return Card(
                                  elevation: 0,
                                  margin: EdgeInsets.zero,
                                  color: const Color(0xFFF7F1FC),
                                  clipBehavior: Clip.antiAlias,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: CheckboxListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    tileColor: Colors.transparent,
                                    value: selected,
                                    onChanged: (value) {
                                      setState(() {
                                        if (value == true) {
                                          _selectedTrashIds.add(task.id);
                                        } else {
                                          _selectedTrashIds.remove(task.id);
                                        }
                                      });
                                    },
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: Text(task.title),
                                    subtitle: _buildTaskSubtitle(task),
                                    secondary: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          onPressed: () async {
                                            await widget.database
                                                .restoreTask(task.id);
                                            if (mounted) {
                                              setState(() => _selectedTrashIds
                                                  .remove(task.id));
                                            }
                                          },
                                          icon: const Icon(Icons.restore),
                                          tooltip: '恢复',
                                        ),
                                        IconButton(
                                          onPressed: () =>
                                              _confirmPermanentDelete([task.id]),
                                          icon: const Icon(Icons.delete_forever),
                                          tooltip: '永久删除',
                                        ),
                                      ],
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
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
                final orderedTasks = _sortTasks(tasks);
                final pending = tasks.where((task) => !task.completed).length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '收件箱',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: Text('$pending 个待办')),
                        PopupMenuButton<TaskSortMode>(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          menuPadding: EdgeInsets.zero,
                          onSelected: (value) =>
                              setState(() => _sortMode = value),
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: TaskSortMode.createdAt,
                              child: Text(
                                '创建时间',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ),
                            PopupMenuItem(
                              value: TaskSortMode.title,
                              child: Text(
                                '标题字典序',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ),
                            PopupMenuItem(
                              value: TaskSortMode.dueAt,
                              child: Text(
                                '截止时间',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ),
                            PopupMenuItem(
                              value: TaskSortMode.manual,
                              child: Text(
                                '手动排序',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_sortModeLabel()),
                                const SizedBox(width: 8),
                                const Icon(Icons.expand_more, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: orderedTasks.isEmpty
                          ? const Center(child: Text('暂无待办，点击右下角新增任务'))
                          : ReorderableListView.builder(
                              buildDefaultDragHandles: true,
                              proxyDecorator: (child, index, animation) => child,
                              itemCount: orderedTasks.length,
                              onReorderItem: (oldIndex, newIndex) =>
                                  _reorderTasks(
                                orderedTasks,
                                oldIndex,
                                newIndex,
                              ),
                              itemBuilder: (context, index) {
                                final task = orderedTasks[index];
                                return Card(
                                  key: ValueKey(task.id),
                                  elevation: 0,
                                  margin: EdgeInsets.zero,
                                  color: const Color(0xFFF7F1FC),
                                  clipBehavior: Clip.antiAlias,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: GestureDetector(
                                    onSecondaryTapDown: (details) =>
                                        _showTaskMenu(
                                      task,
                                      details.globalPosition,
                                    ),
                                    onLongPress: () =>
                                        _showTaskEditor(task: task),
                                    child: CheckboxListTile(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      tileColor: Colors.transparent,
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
