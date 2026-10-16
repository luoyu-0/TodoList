package com.example.todolist

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

class AlarmSoundService : Service() {
    companion object {
        private const val SERVICE_CHANNEL = "todo_alarm_service_v4"
        private const val ALERT_CHANNEL = "todo_alarm_alert_v5"
        private const val SERVICE_ID = 88001
        const val ALERT_TAG = "todo_task_alert"
    }

    private var ringtone: Ringtone? = null
    private var fallbackTone: ToneGenerator? = null
    private var playbackCheck: Runnable? = null
    private var originalAlarmVolume: Int? = null
    private var raisedAlarmVolume: Int? = null
    private val handler = Handler(Looper.getMainLooper())
    private val timeout = Runnable { stopSelf() }
    private val beep = object : Runnable {
        override fun run() {
            fallbackTone?.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 600)
            handler.postDelayed(this, 2000)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "待办任务"
        val taskId = intent?.getStringExtra("taskId")
        val alarmId = intent?.getIntExtra("id", 0) ?: 0
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(SERVICE_CHANNEL, "闹钟运行状态", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "保持正在响铃的提醒运行"
                    setSound(null, null)
                },
            )
            manager.createNotificationChannel(
                NotificationChannel(ALERT_CHANNEL, "待办闹钟提醒", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "到点时在通知栏显示任务提醒"
                    setSound(null, null)
                    enableVibration(true)
                },
            )
        }
        val openTask = PendingIntent.getActivity(
            this, alarmId,
            Intent(this, MainActivity::class.java)
                .putExtra("taskId", taskId)
                .putExtra("notificationId", alarmId)
                .putExtra("fromAlarm", true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val dismiss = PendingIntent.getBroadcast(
            this, alarmId, Intent(this, AlarmDismissReceiver::class.java)
                .putExtra("notificationId", alarmId),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val serviceBuilder = if (Build.VERSION.SDK_INT >= 26)
            Notification.Builder(this, SERVICE_CHANNEL) else Notification.Builder(this)
        val serviceNotification = serviceBuilder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("TodoList · 闹钟响铃中")
            .setContentText(title)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setPriority(Notification.PRIORITY_LOW)
            .setContentIntent(openTask)
            .setOngoing(true)
            .build()
        startForeground(SERVICE_ID, serviceNotification)
        val alertBuilder = if (Build.VERSION.SDK_INT >= 26)
            Notification.Builder(this, ALERT_CHANNEL) else Notification.Builder(this)
        val alertNotification = alertBuilder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("TodoList · 任务提醒")
            .setContentText(title)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setPriority(Notification.PRIORITY_MAX)
            .setContentIntent(openTask)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "关闭提醒", dismiss)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .build()
        manager.notify(ALERT_TAG, alarmId, alertNotification)
        AlarmScheduler.setStatus(this, "闹钟服务已启动，任务通知已发布")

        ringtone?.stop()
        playbackCheck?.let { handler.removeCallbacks(it) }
        handler.removeCallbacks(beep)
        fallbackTone?.release()
        fallbackTone = null
        val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        raiseAlarmVolume(audioManager)
        val volume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
        val importance = if (Build.VERSION.SDK_INT >= 26)
            manager.getNotificationChannel(ALERT_CHANNEL)?.importance else null
        try {
            val uri = RingtoneManager.getActualDefaultRingtoneUri(
                this, RingtoneManager.TYPE_ALARM,
            ) ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ringtone = RingtoneManager.getRingtone(this, uri)
            ringtone?.audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            if (Build.VERSION.SDK_INT >= 28) ringtone?.volume = 1.0f
            if (Build.VERSION.SDK_INT >= 28) ringtone?.isLooping = true
            ringtone?.play()
            playbackCheck = Runnable {
                val playing = ringtone?.isPlaying == true
                AlarmScheduler.setStatus(
                    this,
                    "铃声播放=$playing，闹钟音量=$volume，通知频道级别=$importance",
                )
                if (!playing) startFallbackTone()
            }
            handler.postDelayed(playbackCheck!!, 1000)
        } catch (error: Exception) {
            AlarmScheduler.setStatus(this, "铃声启动失败：${error.javaClass.simpleName}，正在使用备用提示音")
            startFallbackTone()
        }
        handler.removeCallbacks(timeout)
        handler.postDelayed(timeout, 60_000)
        return START_NOT_STICKY
    }

    private fun startFallbackTone() {
        try {
            fallbackTone = ToneGenerator(AudioManager.STREAM_ALARM, 100)
            handler.post(beep)
        } catch (error: Exception) {
            AlarmScheduler.setStatus(this, "备用提示音失败：${error.javaClass.simpleName}")
        }
    }

    private fun raiseAlarmVolume(audio: AudioManager) {
        if (originalAlarmVolume != null) return
        val current = audio.getStreamVolume(AudioManager.STREAM_ALARM)
        val maximum = audio.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        // 尊重用户主动设置的静音；仅对非静音铃声临时提高音量。
        if (current == 0 || maximum == 0) return
        val target = maxOf(current, (maximum * 0.8f).toInt().coerceAtLeast(1))
        if (target == current) return
        try {
            audio.setStreamVolume(AudioManager.STREAM_ALARM, target, 0)
            val actual = audio.getStreamVolume(AudioManager.STREAM_ALARM)
            if (actual > current) {
                originalAlarmVolume = current
                raisedAlarmVolume = actual
            }
        } catch (_: SecurityException) {
            // 系统可能因勿扰模式拒绝调节，仍按当前音量播放。
        }
    }

    override fun onDestroy() {
        handler.removeCallbacks(timeout)
        playbackCheck?.let { handler.removeCallbacks(it) }
        handler.removeCallbacks(beep)
        fallbackTone?.release()
        fallbackTone = null
        ringtone?.stop()
        ringtone = null
        val original = originalAlarmVolume
        val raised = raisedAlarmVolume
        if (original != null && raised != null) {
            val audio = getSystemService(AUDIO_SERVICE) as AudioManager
            if (audio.getStreamVolume(AudioManager.STREAM_ALARM) == raised) {
                try {
                    audio.setStreamVolume(AudioManager.STREAM_ALARM, original, 0)
                } catch (_: SecurityException) {
                    // 不覆盖系统的勿扰策略。
                }
            }
        }
        originalAlarmVolume = null
        raisedAlarmVolume = null
        if (Build.VERSION.SDK_INT >= 33) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }
}
