package com.example.gf_alarm_api

import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Handler
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

class AlarmSoundService : Service() {

    companion object {
        private const val TAG = "AlarmSoundService"

        private const val NOTI_ID = 88001
        const val ACTION_STOP = "STOP"
        private const val CHANNEL_ID = "alarm_channel_v4"

        // 기본 자동 종료(ms) — 인텐트로 덮어쓸 수 있음(EXTRA_AUTO_STOP_MS)
        private const val DEFAULT_AUTO_STOP_MS = 60_000L

        // Intent Extras (FCM data → BackgroundReceiver에서 그대로 전달)
        const val EXTRA_TITLE = "title"                  // 알림 제목
        const val EXTRA_BODY = "body"                    // 알림 본문
        const val EXTRA_AUTO_STOP_MS = "auto_stop_ms"    // Long(ms). <=0 이면 자동종료 끔
        const val EXTRA_GAIN = "gain"                    // Float 0.0~1.0 (MediaPlayer 스케일 볼륨)
        const val EXTRA_SET_STREAM_VOL = "set_stream_volume" // Int 0~max (시스템 알람 볼륨 절대값)
        const val EXTRA_SOUND_RES_NAME = "sound_res"     // String (ex: "critical_alert")
        const val EXTRA_SILENT = "silent"                // Boolean. true(기본)=조용한 서비스 알림

        // Flutter SharedPreferences 파일/키
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val K_CRITICAL_ON = "flutter.critical_alarm_enabled"
    }

    private var player: MediaPlayer? = null
    private val handler by lazy { Handler(mainLooper) }
    private var autoStopRunnable: Runnable? = null

    // 시스템 알람 스트림 볼륨 원복을 위한 저장
    private var origAlarmVol: Int? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelfSafely()
            return START_NOT_STICKY
        }

        // ✅ 안전장치: Flutter 설정에서 긴급 알람이 OFF면 즉시 종료
        val prefs = getSharedPreferences(FLUTTER_PREFS, MODE_PRIVATE)
        val criticalOn = prefs.getBoolean(K_CRITICAL_ON, true)
        if (!criticalOn) {
            Log.i(TAG, "Critical alarm disabled by user setting. Service will stop.")
            stopSelfSafely()
            return START_NOT_STICKY
        }

        // 루프 여부(끌 때까지 울림)
        val loop = intent?.getBooleanExtra("loop", false) ?: false

        // ───────────────────────────────────────────
        // 알림(서비스용, 조용하게) 띄우기
        // ───────────────────────────────────────────
        startAsForeground(
            title = intent?.getStringExtra(EXTRA_TITLE) ?: "긴급 알림 재생 중",
            body = intent?.getStringExtra(EXTRA_BODY) ?: "잠시 후 자동으로 종료됩니다.",
            silent = intent?.getBooleanExtra(EXTRA_SILENT, true) ?: true,
        )

        // ───────────────────────────────────────────
        // 사운드 재생 시작 (loop 지원)
        // ───────────────────────────────────────────
        startPlayer(
            gain = (intent?.getFloatExtra(EXTRA_GAIN, 1.0f) ?: 1.0f).coerceIn(0f, 1f),
            absAlarmVol = intent?.getIntExtra(EXTRA_SET_STREAM_VOL, -1) ?: -1,
            soundResName = intent?.getStringExtra(EXTRA_SOUND_RES_NAME),
            loop = loop
        )

        // ───────────────────────────────────────────
        // 자동 종료 타이머 (loop면 끔)
        // ───────────────────────────────────────────
        val autoStopMs = intent?.getLongExtra(EXTRA_AUTO_STOP_MS, DEFAULT_AUTO_STOP_MS)
            ?: DEFAULT_AUTO_STOP_MS
        resetAutoStop(if (loop) 0L else autoStopMs)

        return START_STICKY
    }

    private fun resetAutoStop(ms: Long) {
        autoStopRunnable?.let { handler.removeCallbacks(it) }
        if (ms > 0) {
            autoStopRunnable = Runnable { stopSelfSafely() }
            handler.postDelayed(autoStopRunnable!!, ms)
        } else {
            autoStopRunnable = null
        }
    }

    private fun startAsForeground(title: String, body: String, silent: Boolean) {
        val stopIntent = Intent(this, AlarmSoundService::class.java).apply { action = ACTION_STOP }
        val stopPi = PendingIntent.getService(
            this, 3001, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setOngoing(true)
            .addAction(0, "중지", stopPi)

        if (silent) {
            // ✅ 조용한 서비스 알림 → Heads-up 방지 (팝업은 수신 시 1회만)
            builder.setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setSilent(true)
        } else {
            // 필요 시(특수 케이스) 팝업 알림로 승격
            builder.setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
        }

        startForeground(NOTI_ID, builder.build())
    }

    private fun startPlayer(
        gain: Float,
        absAlarmVol: Int,
        soundResName: String?,
        loop: Boolean
    ) {
        if (player != null) return
        try {
            // (선택) 시스템 알람 스트림 볼륨을 임시로 절대값으로 설정
            if (absAlarmVol >= 0) {
                try {
                    val am = getSystemService(AUDIO_SERVICE) as AudioManager
                    val max = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                    val newLevel = absAlarmVol.coerceIn(0, max)
                    val oldLevel = am.getStreamVolume(AudioManager.STREAM_ALARM)
                    if (origAlarmVol == null) origAlarmVol = oldLevel
                    am.setStreamVolume(AudioManager.STREAM_ALARM, newLevel, 0)
                } catch (e: Throwable) {
                    Log.w(TAG, "setStreamVolume failed", e)
                }
            }

            // 재생할 raw 리소스 선택 (없으면 기본 critical_alert)
            val resId = resolveRawResId(soundResName) ?: R.raw.critical_alert

            player = MediaPlayer.create(this, resId).apply {
                isLooping = loop
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setVolume(gain, gain) // 스케일 볼륨 (0.0~1.0)
                if (!loop) {
                    setOnCompletionListener { stopSelfSafely() } // 1회 재생이면 끝나면 자동 종료
                }
                start()
            }
        } catch (t: Throwable) {
            Log.e(TAG, "startPlayer error", t)
            stopSelfSafely()
        }
    }

    private fun resolveRawResId(name: String?): Int? {
        if (name.isNullOrBlank()) return null
        val id = resources.getIdentifier(name, "raw", packageName)
        return if (id != 0) id else null
    }

    private fun stopSelfSafely() {
        try {
            player?.setOnCompletionListener(null)
            player?.stop()
            player?.release()
        } catch (_: Throwable) {}
        player = null

        // 시스템 알람 볼륨 원복
        origAlarmVol?.let {
            try {
                val am = getSystemService(AUDIO_SERVICE) as AudioManager
                am.setStreamVolume(AudioManager.STREAM_ALARM, it, 0)
            } catch (_: Throwable) {}
        }
        origAlarmVol = null

        autoStopRunnable?.let { handler.removeCallbacks(it) }
        autoStopRunnable = null

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        stopSelfSafely()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}