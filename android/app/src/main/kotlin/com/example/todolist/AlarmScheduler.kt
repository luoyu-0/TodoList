package com.example.todolist

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

object AlarmScheduler {
    private const val PREFS = "todolist_alarms"
    private const val KEY = "scheduled"
    private const val DIAGNOSTICS = "last_status"

    fun setStatus(context: Context, status: String) {
        val time = java.text.DateFormat.getTimeInstance().format(java.util.Date())
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(DIAGNOSTICS, "$time · $status").apply()
    }

    fun status(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(DIAGNOSTICS, "尚未触发提醒") ?: "尚未触发提醒"

    fun test(context: Context) {
        val at = System.currentTimeMillis() + 10_000
        schedule(context, 999, "提醒测试", at, null)
        setStatus(context, "测试提醒已安排，10 秒后触发")
    }

    private fun intent(context: Context, id: Int, title: String, taskId: String?): PendingIntent {
        val alarm = Intent(context, AlarmReceiver::class.java)
            .putExtra("id", id)
            .putExtra("title", title)
            .putExtra("taskId", taskId)
        return PendingIntent.getBroadcast(
            context, id, alarm,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun schedule(context: Context, id: Int, title: String, at: Long, taskId: String?) {
        if (at <= System.currentTimeMillis()) return
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val operation = intent(context, id, title, taskId)
        if (Build.VERSION.SDK_INT < 31 || manager.canScheduleExactAlarms()) {
            val launch = PendingIntent.getActivity(
                context, id,
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            manager.setAlarmClock(AlarmManager.AlarmClockInfo(at, launch), operation)
        } else {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, operation)
        }
    }

    fun sync(context: Context, alarms: List<Map<String, Any>>) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val old = JSONArray(prefs.getString(KEY, "[]"))
        for (index in 0 until old.length()) {
            val item = old.getJSONObject(index)
            manager.cancel(intent(context, item.getInt("id"), item.getString("title"), item.optString("taskId", null)))
        }
        val stored = JSONArray()
        for (item in alarms) {
            val id = (item["id"] as Number).toInt()
            val title = item["title"] as String
            val taskId = item["taskId"] as? String
            val at = (item["at"] as Number).toLong()
            if (at <= System.currentTimeMillis()) continue
            stored.put(JSONObject().put("id", id).put("title", title).put("at", at).put("taskId", taskId))
            schedule(context, id, title, at, taskId)
        }
        prefs.edit().putString(KEY, stored.toString()).apply()
    }

    fun restore(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val stored = JSONArray(prefs.getString(KEY, "[]"))
        for (index in 0 until stored.length()) {
            val item = stored.getJSONObject(index)
            schedule(context, item.getInt("id"), item.getString("title"), item.getLong("at"), item.optString("taskId", null))
        }
    }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        AlarmScheduler.setStatus(context, "定时器已触发，准备启动闹钟服务")
        val service = Intent(context, AlarmSoundService::class.java)
            .putExtra("id", intent.getIntExtra("id", 0))
            .putExtra("title", intent.getStringExtra("title") ?: "待办任务")
            .putExtra("taskId", intent.getStringExtra("taskId"))
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                context.startForegroundService(service)
            } else {
                context.startService(service)
            }
        } catch (error: Exception) {
            AlarmScheduler.setStatus(context, "闹钟服务启动失败：${error.javaClass.simpleName}")
        }
    }
}

class AlarmBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            AlarmScheduler.restore(context)
        }
    }
}

class AlarmDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("notificationId", 0)
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager)
            .cancel(AlarmSoundService.ALERT_TAG, id)
        context.stopService(Intent(context, AlarmSoundService::class.java))
    }
}
