import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import 'data/local/app_database.dart';
import 'services/notification_service.dart';
import 'services/reminder_time.dart';
import 'app_theme.dart';
import 'reminder_popup.dart';

// 独立提醒引擎不初始化数据库、托盘或任务调度。
@pragma('vm:entry-point')
void reminderMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReminderPopupApp());
}

enum TaskSortMode { createdAt, title, dueAt, manual }

bool _isPinnedWindow = false;
Future<void> Function()? _beforeApplicationExit;

class _TodoListTrayController {
  late final tray.TrayIcon _trayIcon;
  bool _isExiting = false;

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

  void _exitApplication() {
    if (_isExiting) return;
    _isExiting = true;
    unawaited(_exitApplicationAsync());
  }

  Future<void> _exitApplicationAsync() async {
    // 先让窗口和托盘立即消失，避免等待窗口销毁时看起来像卡死。
    unawaited(windowManager.hide());
    _trayIcon.setVisible(false);
    // 托盘菜单回调仍在原生事件中执行，延迟销毁以避免中断当前菜单事件。
    Timer.run(_trayIcon.dispose);
    try {
      await _beforeApplicationExit?.call();
    } finally {
      // 保存完成后直接结束进程，避免 window_manager.destroy 等待原生消息循环。
      exit(0);
    }
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
  await TodoNotificationService.instance.initialize();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    final trayController = _TodoListTrayController();
    await trayController.initialize();
    const MethodChannel('com.todolist/reminder')
        .setMethodCallHandler((call) async {
          if (call.method == 'open') await trayController._showWindow();
        });
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
      theme: buildAppTheme(),
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
  static const _openTaskChannel = MethodChannel('com.todolist/open_task');
  final _taskListScrollController = ScrollController();
  final _targetTaskKey = GlobalKey();
  String? _targetTaskId;
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isPinned = false;
  bool _isMaximized = false;
  bool _showTrash = false;
  TaskSortMode _sortMode = TaskSortMode.createdAt;
  bool _sortAscending = false;
  final _selectedTrashIds = <String>{};
  final _pinnedHiddenTaskIds = <String>{};
  final _manualTaskOrder = <String>[];
  StreamSubscription<List<Task>>? _taskSubscription;
  bool _manualOrderDirty = false;
  Offset? _lastPinnedPosition;
  Size? _lastPinnedSize;
  bool _lastPinnedAlwaysOnTop = true;
  bool _isAlwaysOnTop = false;
  Timer? _trashCleanupTimer;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _openTaskChannel.setMethodCallHandler((call) async {
        if (call.method == 'openTask' && call.arguments is String) {
          await _openTaskFromNotification(call.arguments as String);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final taskId = await _openTaskChannel.invokeMethod<String>(
          'takePendingTaskId',
        );
        if (taskId != null) await _openTaskFromNotification(taskId);
      });
    }
    _beforeApplicationExit = _prepareForApplicationExit;
    _taskSubscription = widget.database.watchInbox().listen(
      (tasks) => unawaited(
        TodoNotificationService.instance.syncTasks(tasks, widget.database),
      ),
    );
    _loadWindowState();
    _loadSortMode();
    _trashCleanupTimer = Timer.periodic(
      const Duration(hours: 24),
      (_) => widget.database.purgeExpiredTrash(),
    );
  }

  Future<void> _loadSortMode() async {
    final value = await widget.database.getSortMode();
    final ascending = await widget.database.getSortAscending();
    final mode = TaskSortMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () => TaskSortMode.createdAt,
    );
    if (mounted) {
      setState(() {
        _sortMode = mode;
        _sortAscending = ascending;
      });
    }
  }

  Future<void> _loadWindowState() async {
    if (Platform.isWindows) {
      final maximized = await windowManager.isMaximized();
      if (mounted) setState(() => _isMaximized = maximized);
    }
  }

  @override
  void dispose() {
    if (Platform.isAndroid) _openTaskChannel.setMethodCallHandler(null);
    _taskListScrollController.dispose();
    _beforeApplicationExit = null;
    _taskSubscription?.cancel();
    _titleController.dispose();
    _noteController.dispose();
    _trashCleanupTimer?.cancel();
    super.dispose();
  }

  Future<void> _openTaskFromNotification(String taskId) async {
    final tasks = await widget.database.watchInbox().first;
    if (!mounted) return;
    final ordered = _sortTasks(tasks);
    final index = ordered.indexWhere((task) => task.id == taskId);
    if (index < 0) return;
    setState(() {
      _showTrash = false;
      _targetTaskId = taskId;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_taskListScrollController.hasClients) return;
    final position = _taskListScrollController.position;
    final offset = position.maxScrollExtent * index / ordered.length;
    _taskListScrollController.jumpTo(offset.clamp(0, position.maxScrollExtent));
    await WidgetsBinding.instance.endOfFrame;
    final target = _targetTaskKey.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(
        target,
        alignment: 0.25,
        duration: const Duration(milliseconds: 250),
      );
    } else if (mounted) {
      // 高度差异很大的列表中仍直接打开准确的任务详情。
      await _showTaskEditor(task: ordered[index]);
    }
  }

  Future<void> _showTaskEditor({Task? task}) async {
    _titleController.text = task?.title ?? '';
    _noteController.text = task?.note ?? '';
    bool saving = false;
    String? editorError;
    DateTime? selectedDueAt = task?.dueAt;
    bool dueHasTime = task?.dueHasTime ?? false;
    bool reminderEnabled = task?.reminderEnabled ?? true;
    bool reminderEdited = task?.reminderAt != null;
    DateTime? selectedReminderAt =
        task?.reminderAt ??
        (selectedDueAt == null
            ? null
            : defaultReminderAt(selectedDueAt, dueHasTime));
    final additionalReminders = task == null
        ? <DateTime>[]
        : (await widget.database.getAdditionalReminders([task.id]))
              .map((item) => item.remindAt)
              .toList();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
                    autofocus: false,
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
                  Card(
                    elevation: 0,
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      shape: const Border(),
                      collapsedShape: const Border(),
                      title: const Text('截止日期'),
                      subtitle: Text(
                        selectedDueAt == null
                            ? '未设置'
                            : dueHasTime
                            ? _formatDateTime(selectedDueAt!)
                            : '${_formatDate(selectedDueAt!)} · 全天',
                      ),
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      children: [
                        Wrap(
                          alignment: WrapAlignment.start,
                          spacing: 4,
                          children: [
                            TextButton.icon(
                              onPressed: () async {
                                FocusScope.of(context).unfocus();
                                final date = await showDatePicker(
                                  context: context,
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime(2100),
                                  initialDate:
                                      selectedDueAt != null &&
                                          selectedDueAt!.isBefore(
                                            DateTime.now(),
                                          )
                                      ? DateTime.now()
                                      : selectedDueAt ?? DateTime.now(),
                                );
                                if (date != null && dialogContext.mounted) {
                                  final current = selectedDueAt ?? date;
                                  setDialogState(() {
                                    selectedDueAt = DateTime(
                                      date.year,
                                      date.month,
                                      date.day,
                                      dueHasTime ? current.hour : 0,
                                      dueHasTime ? current.minute : 0,
                                    );
                                    if (!reminderEdited) {
                                      selectedReminderAt = defaultReminderAt(
                                        selectedDueAt!,
                                        dueHasTime,
                                      );
                                    }
                                  });
                                }
                              },
                              icon: const Icon(Icons.calendar_today_outlined),
                              label: const Text('选择日期'),
                            ),
                            if (selectedDueAt != null)
                              TextButton.icon(
                                onPressed: () async {
                                  FocusScope.of(context).unfocus();
                                  final time = await _pickWheelDateTime(
                                    selectedDueAt!,
                                    CupertinoDatePickerMode.time,
                                  );
                                  if (time != null && dialogContext.mounted) {
                                    setDialogState(() {
                                      dueHasTime = true;
                                      selectedDueAt = DateTime(
                                        selectedDueAt!.year,
                                        selectedDueAt!.month,
                                        selectedDueAt!.day,
                                        time.hour,
                                        time.minute,
                                      );
                                      if (!reminderEdited) {
                                        selectedReminderAt = selectedDueAt;
                                      }
                                    });
                                  }
                                },
                                icon: const Icon(Icons.access_time_outlined),
                                label: const Text('选择时间'),
                              ),
                            if (selectedDueAt != null && dueHasTime)
                              TextButton(
                                onPressed: () => setDialogState(() {
                                  dueHasTime = false;
                                  selectedDueAt = DateTime(
                                    selectedDueAt!.year,
                                    selectedDueAt!.month,
                                    selectedDueAt!.day,
                                  );
                                  if (!reminderEdited) {
                                    selectedReminderAt = defaultReminderAt(
                                      selectedDueAt!,
                                      false,
                                    );
                                  }
                                }),
                                child: const Text('设为全天'),
                              ),
                            if (selectedDueAt != null)
                              IconButton(
                                onPressed: () => setDialogState(() {
                                  selectedDueAt = null;
                                  dueHasTime = false;
                                  selectedReminderAt = null;
                                  reminderEdited = false;
                                  additionalReminders.clear();
                                }),
                                icon: const Icon(Icons.clear),
                                tooltip: '清除日期',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('提醒'),
                          subtitle: Text(
                            selectedDueAt == null
                                ? '设置截止日期后可开启提醒'
                                : reminderEnabled
                                ? '到时间通知我'
                                : '已关闭，提醒时间已保留',
                          ),
                          value: selectedDueAt != null && reminderEnabled,
                          onChanged: selectedDueAt == null
                              ? null
                              : (enabled) => setDialogState(
                                  () => reminderEnabled = enabled,
                                ),
                        ),
                        if (selectedDueAt != null && reminderEnabled) ...[
                          Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              title: const Text('提醒 1'),
                              subtitle: Text(
                                _formatDateTime(
                                  selectedReminderAt ??
                                      defaultReminderAt(
                                        selectedDueAt!,
                                        dueHasTime,
                                      ),
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                FocusScope.of(context).unfocus();
                                final picked = await _pickWheelDateTime(
                                  selectedReminderAt ??
                                      defaultReminderAt(
                                        selectedDueAt!,
                                        dueHasTime,
                                      ),
                                  CupertinoDatePickerMode.dateAndTime,
                                );
                                if (picked != null && dialogContext.mounted) {
                                  setDialogState(() {
                                    selectedReminderAt = picked;
                                    reminderEdited = true;
                                  });
                                }
                              },
                            ),
                          ),
                          for (
                            var index = 0;
                            index < additionalReminders.length;
                            index++
                          )
                            Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                title: Text('提醒 ${index + 2}'),
                                subtitle: Text(
                                  _formatDateTime(additionalReminders[index]),
                                ),
                                onTap: () async {
                                  final picked = await _pickWheelDateTime(
                                    additionalReminders[index],
                                    CupertinoDatePickerMode.dateAndTime,
                                  );
                                  if (picked != null && dialogContext.mounted) {
                                    setDialogState(() {
                                      additionalReminders[index] = picked;
                                      additionalReminders.sort();
                                    });
                                  }
                                },
                                trailing: IconButton(
                                  tooltip: '删除提醒',
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () => setDialogState(
                                    () => additionalReminders.removeAt(index),
                                  ),
                                ),
                              ),
                            ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () async {
                                final picked = await _pickWheelDateTime(
                                  defaultReminderAt(
                                    selectedDueAt!,
                                    dueHasTime,
                                  ).add(const Duration(hours: 1)),
                                  CupertinoDatePickerMode.dateAndTime,
                                );
                                if (picked != null && dialogContext.mounted) {
                                  setDialogState(() {
                                    if (!additionalReminders.contains(picked) &&
                                        picked !=
                                            (selectedReminderAt ??
                                                defaultReminderAt(
                                                  selectedDueAt!,
                                                  dueHasTime,
                                                ))) {
                                      additionalReminders.add(picked);
                                    }
                                    additionalReminders.sort();
                                  });
                                }
                              },
                              icon: const Icon(Icons.add_alarm_outlined),
                              label: const Text('新增提醒时间'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (editorError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        editorError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final title = _titleController.text.trim();
                if (saving) return;
                if (title.isEmpty) {
                  setDialogState(() => editorError = '请输入任务标题');
                  return;
                }
                setDialogState(() {
                  saving = true;
                  editorError = null;
                });
                try {
                  final note = _noteController.text.trim();
                  if (task == null) {
                    await widget.database.addTask(
                      title: title,
                      note: note.isEmpty ? null : note,
                      dueAt: selectedDueAt,
                      dueHasTime: dueHasTime,
                      reminderAt: selectedReminderAt,
                      reminderEnabled: reminderEnabled,
                      additionalReminders: additionalReminders,
                    );
                  } else {
                    await widget.database.updateTask(
                      id: task.id,
                      title: title,
                      note: note.isEmpty ? null : note,
                      dueAt: selectedDueAt,
                      dueHasTime: dueHasTime,
                      reminderAt: selectedReminderAt,
                      reminderEnabled: reminderEnabled,
                      additionalReminders: additionalReminders,
                    );
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (_) {
                  if (dialogContext.mounted) {
                    setDialogState(() => editorError = '保存失败，请重试');
                  }
                } finally {
                  if (dialogContext.mounted) {
                    setDialogState(() => saving = false);
                  }
                }
              },
              child: Text(saving ? '保存中…' : '保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<DateTime?> _pickWheelDateTime(
    DateTime initial,
    CupertinoDatePickerMode mode,
  ) async {
    var selected = initial;
    final timeController = TextEditingController(
      text:
          '${initial.hour.toString().padLeft(2, '0')}:${initial.minute.toString().padLeft(2, '0')}',
    );
    final timeFocus = FocusNode();
    var invalidTime = false;
    final result = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SizedBox(
              height: MediaQuery.viewInsetsOf(context).bottom > 0
                  ? (mode == CupertinoDatePickerMode.dateAndTime ? 205 : 155)
                  : (mode == CupertinoDatePickerMode.dateAndTime ? 390 : 340),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Expanded(child: Text('滚动选择，或输入 24 小时时间')),
                        TextButton(
                          onPressed: () {
                            final value = with24HourTime(
                              selected,
                              timeController.text,
                            );
                            if (value == null) {
                              setSheetState(() => invalidTime = true);
                              return;
                            }
                            Navigator.pop(sheetContext, value);
                          },
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  ),
                  if (mode == CupertinoDatePickerMode.dateAndTime)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextButton.icon(
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text('日期：${_formatDate(selected)}'),
                          onPressed: () async {
                            timeFocus.unfocus();
                            final date = await showDatePicker(
                              context: context,
                              initialDate: selected,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (date != null) {
                              setSheetState(() {
                                selected = DateTime(
                                  date.year,
                                  date.month,
                                  date.day,
                                  selected.hour,
                                  selected.minute,
                                );
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: timeController,
                      focusNode: timeFocus,
                      keyboardType: TextInputType.datetime,
                      maxLength: 5,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
                      ],
                      onChanged: (_) {
                        if (invalidTime) {
                          setSheetState(() => invalidTime = false);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: '时间（HH:mm）',
                        hintText: '例如 18:30',
                        errorText: invalidTime ? '请输入 00:00–23:59' : null,
                        border: const OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  if (MediaQuery.viewInsetsOf(context).bottom == 0)
                    Expanded(
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.time,
                        initialDateTime: initial,
                        use24hFormat: true,
                        onDateTimeChanged: (value) {
                          selected = DateTime(
                            selected.year,
                            selected.month,
                            selected.day,
                            value.hour,
                            value.minute,
                          );
                          if (!timeFocus.hasFocus) {
                            timeController.text =
                                '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    timeController.dispose();
    timeFocus.dispose();
    return result;
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
      menuPadding: EdgeInsets.zero,
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

  String _formatDateTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${_formatDate(date)} $hour:$minute';
  }

  List<Task> _sortTasks(Iterable<Task> source, {bool completedLast = false}) {
    final result = source.toList();
    if (_sortMode == TaskSortMode.manual) {
      if (_manualTaskOrder.isEmpty) {
        final persistedOrder = [...result]
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        _manualTaskOrder.addAll(persistedOrder.map((task) => task.id));
      } else {
        for (final task in result) {
          if (!_manualTaskOrder.contains(task.id)) {
            _manualTaskOrder.add(task.id);
          }
        }
      }
    }
    result.sort((a, b) {
      if (completedLast && a.completed != b.completed) {
        return a.completed ? 1 : -1;
      }
      final direction = _sortAscending ? 1 : -1;
      switch (_sortMode) {
        case TaskSortMode.title:
          return direction *
              a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case TaskSortMode.dueAt:
          if (a.dueAt == null && b.dueAt == null) return 0;
          if (a.dueAt == null) return 1;
          if (b.dueAt == null) return -1;
          return direction * a.dueAt!.compareTo(b.dueAt!);
        case TaskSortMode.manual:
          final aIndex = _manualTaskOrder.indexOf(a.id);
          final bIndex = _manualTaskOrder.indexOf(b.id);
          if (aIndex != -1 && bIndex != -1) {
            return direction * aIndex.compareTo(bIndex);
          }
          if (aIndex != -1) return -1;
          if (bIndex != -1) return 1;
          return direction * a.sortOrder.compareTo(b.sortOrder);
        case TaskSortMode.createdAt:
          return direction * a.createdAt.compareTo(b.createdAt);
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

  Future<void> _toggleSortDirection() async {
    final nextValue = !_sortAscending;
    setState(() => _sortAscending = nextValue);
    await widget.database.setSortAscending(nextValue);
  }

  Future<void> _reorderTasks(
    List<Task> tasks,
    int oldIndex,
    int newIndex,
  ) async {
    final reordered = [...tasks];
    final task = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, task);
    final switchingToManual = _sortMode != TaskSortMode.manual;
    // 拖动以当前屏幕顺序为准。首次切换到手动排序时使用正序，避免沿用
    // 之前的降序设置导致列表在拖动结束后整体反转。
    final ascending = switchingToManual ? true : _sortAscending;
    final displayedOrder = reordered.map((item) => item.id).toList();
    final persistedOrder = ascending
        ? displayedOrder
        : displayedOrder.reversed.toList();
    _manualTaskOrder
      ..clear()
      ..addAll(persistedOrder);
    _manualOrderDirty = true;
    if (switchingToManual) {
      setState(() {
        _sortMode = TaskSortMode.manual;
        _sortAscending = ascending;
      });
      await widget.database.setSortMode(TaskSortMode.manual.name);
      await widget.database.setSortAscending(ascending);
    } else {
      setState(() {});
    }
    if (!Platform.isWindows) {
      await _flushPendingTaskOrder();
    }
  }

  Future<void> _flushPendingTaskOrder() async {
    if (!_manualOrderDirty || _manualTaskOrder.isEmpty) return;
    await widget.database.updateTaskOrder(_manualTaskOrder);
    _manualOrderDirty = false;
  }

  Future<void> _prepareForApplicationExit() async {
    await _flushPendingTaskOrder();
    await widget.database.close();
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
          Text(task.note!.trim(), maxLines: 2, overflow: TextOverflow.ellipsis),
        if (hasDueDate)
          Text(
            '截止：${task.dueHasTime ? _formatDateTime(task.dueAt!) : _formatDate(task.dueAt!)}',
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
    if (!_isPinned) {
      await windowManager.setAlwaysOnTop(true);
      _isAlwaysOnTop = true;
    } else {
      _isAlwaysOnTop = _lastPinnedAlwaysOnTop;
    }
    _isPinnedWindow = !_isPinned;
    if (_isPinnedWindow) {
      await windowManager.setSkipTaskbar(true);
    }
    if (mounted) setState(() => _isPinned = _isPinnedWindow);
  }

  Future<void> _toggleAlwaysOnTop() async {
    if (!Platform.isWindows) return;
    final nextValue = !await windowManager.isAlwaysOnTop();
    await windowManager.setAlwaysOnTop(nextValue);
    if (mounted) setState(() => _isAlwaysOnTop = nextValue);
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('永久删除任务？'),
        content: Text('将永久删除 ${taskIds.length} 个任务，删除后无法恢复。'),
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

  PreferredSizeWidget _buildAppBar() {
    if (!Platform.isWindows) {
      return AppBar(
        title: const Text(
          'TodoList',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: _toggleTrash,
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '回收站',
          ),
        ],
      );
    }
    return PreferredSize(
      preferredSize: const Size.fromHeight(44),
      child: _buildWindowTitleBar(),
    );
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
            if (Platform.isWindows) ...[
              IconButton(
                onPressed: _togglePinned,
                icon: const Icon(Icons.push_pin, size: 18),
                tooltip: '固定到桌面',
              ),
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
                completedLast: true,
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
                          onPressed: _toggleAlwaysOnTop,
                          icon: Icon(
                            _isAlwaysOnTop
                                ? FluentIcons.pin_off_24_regular
                                : FluentIcons.pin_24_regular,
                          ),
                          tooltip: _isAlwaysOnTop ? '取消始终置顶' : '始终置顶',
                        ),
                        IconButton(
                          onPressed: _togglePinned,
                          icon: const Icon(Icons.push_pin),
                          tooltip: '返回正常窗口',
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
                              onChanged: (value) => widget.database
                                  .setTaskCompleted(task.id, value ?? false),
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
      appBar: _buildAppBar(),
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
                                final selected = _selectedTrashIds.contains(
                                  task.id,
                                );
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
                                            await widget.database.restoreTask(
                                              task.id,
                                            );
                                            if (mounted) {
                                              setState(
                                                () => _selectedTrashIds.remove(
                                                  task.id,
                                                ),
                                              );
                                            }
                                          },
                                          icon: const Icon(Icons.restore),
                                          tooltip: '恢复',
                                        ),
                                        IconButton(
                                          onPressed: () =>
                                              _confirmPermanentDelete([
                                                task.id,
                                              ]),
                                          icon: const Icon(
                                            Icons.delete_forever,
                                          ),
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
      appBar: _buildAppBar(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showTaskEditor(),
        icon: const Icon(Icons.add),
        label: const Text('新增任务'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: Text('$pending 个待办')),
                        IconButton(
                          onPressed: _toggleSortDirection,
                          icon: Icon(
                            _sortAscending
                                ? FluentIcons.arrow_sort_up_24_regular
                                : FluentIcons.arrow_sort_down_24_regular,
                            size: 24,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                          tooltip: _sortAscending ? '升序' : '降序',
                        ),
                        PopupMenuButton<TaskSortMode>(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          menuPadding: EdgeInsets.zero,
                          onSelected: (value) async {
                            setState(() => _sortMode = value);
                            await widget.database.setSortMode(value.name);
                          },
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
                              scrollController: _taskListScrollController,
                              buildDefaultDragHandles: Platform.isWindows,
                              proxyDecorator: (child, index, animation) =>
                                  child,
                              itemCount: orderedTasks.length,
                              onReorderItem: (oldIndex, newIndex) =>
                                  _reorderTasks(
                                    orderedTasks,
                                    oldIndex,
                                    newIndex,
                                  ),
                              itemBuilder: (context, index) {
                                final task = orderedTasks[index];
                                final taskCard = Card(
                                  key: _targetTaskId == task.id
                                      ? _targetTaskKey
                                      : null,
                                  elevation: 0,
                                  margin: EdgeInsets.zero,
                                  color: _targetTaskId == task.id
                                      ? Theme.of(context).colorScheme.primaryContainer
                                      : const Color(0xFFF7F1FC),
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
                                    child: ListTile(
                                      onTap: Platform.isAndroid
                                          ? () => _showTaskEditor(task: task)
                                          : null,
                                      leading: Checkbox(
                                        value: task.completed,
                                        onChanged: (value) =>
                                            widget.database.setTaskCompleted(
                                              task.id,
                                              value ?? false,
                                            ),
                                      ),
                                      title: Text(
                                        task.title,
                                        style: TextStyle(
                                          decoration: task.completed
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                      subtitle: _buildTaskSubtitle(task),
                                      trailing: IconButton(
                                        onPressed: () => widget.database
                                            .softDeleteTask(task.id),
                                        icon: const Icon(Icons.delete_outline),
                                        tooltip: '移入回收站',
                                      ),
                                    ),
                                  ),
                                );
                                if (Platform.isAndroid) {
                                  return ReorderableDelayedDragStartListener(
                                    key: ValueKey(task.id),
                                    index: index,
                                    child: taskCard,
                                  );
                                }
                                return KeyedSubtree(
                                  key: ValueKey(task.id),
                                  child: taskCard,
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
