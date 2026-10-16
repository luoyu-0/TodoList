import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

const reminderWindowChannel = MethodChannel('com.todolist/reminder_window');

class ReminderPopupApp extends StatelessWidget {
  const ReminderPopupApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: const ReminderCard(),
  );
}

class ReminderCard extends StatefulWidget {
  const ReminderCard({super.key});

  @override
  State<ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends State<ReminderCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 140),
  );
  Timer? _timer;
  String _title = '';
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    reminderWindowChannel.setMethodCallHandler((call) async {
      if (call.method == 'show') {
        _timer?.cancel();
        setState(() {
          _title = call.arguments as String;
          _closing = false;
        });
        _animation.forward(from: 0);
        // 内容绘制完成后再显示原生窗口，避免旧内容闪现。
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) await reminderWindowChannel.invokeMethod<void>('present');
        _timer = Timer(const Duration(seconds: 20), () => _close());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reminderWindowChannel.invokeMethod<void>('ready');
    });
  }

  Future<void> _close({bool open = false}) async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    await _animation.reverse();
    if (mounted) {
      await reminderWindowChannel.invokeMethod<void>(open ? 'open' : 'dismiss');
    }
  }

  @override
  void dispose() {
    reminderWindowChannel.setMethodCallHandler(null);
    _timer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: FadeTransition(
        opacity: CurvedAnimation(parent: _animation, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween(begin: const Offset(0, .06), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: _animation, curve: Curves.easeOutCubic),
              ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.notifications_active_outlined,
                        size: 22,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TodoList',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '任务提醒',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭提醒',
                      onPressed: () => _close(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      _title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(height: 1.5, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => _close(),
                      child: const Text('关闭'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => _close(open: true),
                      child: const Text('打开 TodoList'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
