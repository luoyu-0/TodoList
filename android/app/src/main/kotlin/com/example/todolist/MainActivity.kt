package com.example.todolist

import android.content.Intent
import android.os.Bundle
import android.app.NotificationManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingTaskId: String? = null
    private var openTaskChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingTaskId = intent?.getStringExtra("taskId")
        super.onCreate(savedInstanceState)
        acknowledgeReminder(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        acknowledgeReminder(intent)
        val taskId = intent.getStringExtra("taskId") ?: return
        pendingTaskId = taskId
        openTaskChannel?.invokeMethod("openTask", taskId, object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (pendingTaskId == taskId) pendingTaskId = null
            }
            override fun error(code: String, message: String?, details: Any?) {}
            override fun notImplemented() {}
        })
    }

    private fun acknowledgeReminder(intent: Intent?) {
        if (intent?.getBooleanExtra("fromAlarm", false) != true) return
        stopService(Intent(this, AlarmSoundService::class.java))
        val notificationId = intent.getIntExtra("notificationId", 0)
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(AlarmSoundService.ALERT_TAG, notificationId)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        openTaskChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.todolist/open_task")
        openTaskChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePendingTaskId" -> {
                    result.success(pendingTaskId)
                    pendingTaskId = null
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.todolist/alarm")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "sync" -> {
                            val alarms = call.argument<List<Map<String, Any>>>("alarms") ?: emptyList()
                            AlarmScheduler.sync(this, alarms)
                            result.success(null)
                        }
                        "test" -> {
                            AlarmScheduler.test(this)
                            result.success(null)
                        }
                        "status" -> result.success(AlarmScheduler.status(this))
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("alarm_sync_failed", error.message, null)
                }
            }
    }
}
