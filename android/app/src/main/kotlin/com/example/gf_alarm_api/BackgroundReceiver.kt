// android/app/src/main/kotlin/com/example/gf_alarm_api/BackgroundReceiver.kt
package com.example.gf_alarm_api

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject

class BackgroundReceiver : FirebaseMessagingService() {

    companion object {
        private const val TAG = "BackgroundReceiver"
        private const val CH_CRITICAL = "alarm_channel_v4"
        private const val CH_NORMAL   = "normal_channel_v1"

        // Flutter SharedPreferences 파일/키 규칙
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val K_CRITICAL_ON = "flutter.critical_alarm_enabled"
        private const val K_NORMAL_ON   = "flutter.normal_alarm_enabled"
        private const val K_UNTIL_STOP  = "flutter.critical_until_stopped"
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val d = message.data ?: emptyMap()
        val title = d["title"] ?: "알림"
        val body  = d["body"] ?: ""
        val notifId = (d["notifId"] ?: System.currentTimeMillis().toString()).hashCode()

        // ── 앱 설정 읽기 (Flutter에서 저장한 값) ─────────────────────────
        val prefs = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val criticalOn   = prefs.getBoolean(K_CRITICAL_ON, true)
        val normalOn     = prefs.getBoolean(K_NORMAL_ON,   true)
        val untilStopped = prefs.getBoolean(K_UNTIL_STOP,  true)

        // (참고 로그) 서버 payload에 critical 힌트가 들어와도 '참고용'만 사용
        val iosCfgRaw = d["ios_config"]
        var payloadCritical = false
        try {
            if (!iosCfgRaw.isNullOrBlank()) {
                val iosObj = JSONObject(iosCfgRaw)
                val iosCrit = iosObj.optBoolean("critical", false)
                val iosIL   = iosObj.optString("interruptionLevel") == "critical"
                payloadCritical = iosCrit || iosIL
            }
            val topCrit = (d["critical"] == "true" || d["critical"] == "1"
                    || d["interruptionLevel"] == "critical")
            payloadCritical = payloadCritical || topCrit
        } catch (_: Throwable) { /* no-op */ }

        Log.d(
            TAG,
            "onMessageReceived id=${message.messageId} " +
            "settings(criticalOn=$criticalOn, normalOn=$normalOn, untilStopped=$untilStopped) " +
            "payloadCritical=$payloadCritical"
        )

        // 채널 보장(앱 프로세스가 없을 때도 안전하게 생성)
        ensureChannels()

        // ── 정책: 서버 플래그와 무관하게 '앱 설정'만으로 동작 결정 ─────────
        if (criticalOn) {
            // 1) 긴급 알람: 네이티브 사운드 서비스 시작 (무음/방해금지 우회)
            try {
                val svc = Intent(this, AlarmSoundService::class.java).apply {
                    putExtra(AlarmSoundService.EXTRA_TITLE, d["svc_title"] ?: title)
                    putExtra(AlarmSoundService.EXTRA_BODY,  d["svc_body"]  ?: body)

                    // '끌 때까지 울림'이면 자동 종료 끔(0L), 1회 울림이면 60초 등 적절히 유지
                    putExtra(
                        AlarmSoundService.EXTRA_AUTO_STOP_MS,
                        if (untilStopped) 0L else 60_000L
                    )

                    // 재생 볼륨/리소스(옵션)
                    putExtra(AlarmSoundService.EXTRA_GAIN, (d["gain"]?.toFloatOrNull() ?: 1.0f))
                    d["alarm_stream_volume"]?.toIntOrNull()?.let {
                        putExtra(AlarmSoundService.EXTRA_SET_STREAM_VOL, it)
                    }
                    putExtra(AlarmSoundService.EXTRA_SOUND_RES_NAME, d["sound_res"] ?: "critical_alert")

                    // 서비스 자체 알림은 조용히(팝업은 별도 Heads-up으로 한 번만)
                    putExtra(AlarmSoundService.EXTRA_SILENT, true)

                    // (옵션) 루프 힌트—현 서비스 구현이 읽지 않더라도 향후 확장 대비
                    putExtra("loop", untilStopped)
                }
                startForegroundService(svc)
            } catch (t: Throwable) {
                Log.e(TAG, "startForegroundService failed", t)
            }

            // 2) Heads-up(알람 채널) 한 번 표시 (중지 액션 포함)
            postNotification(notifId, title, body, d, channelId = CH_CRITICAL, headsUp = true)
            return
        }

        // 긴급 OFF → 일반 알람이 ON이면 일반 채널로 표시(무음/방해금지 우회 없음)
        if (normalOn) {
            postNotification(notifId, title, body, d, channelId = CH_NORMAL, headsUp = false)
        } else {
            Log.i(TAG, "Notification suppressed by user settings (both OFF).")
        }
    }

    private fun postNotification(
        notifId: Int,
        title: String,
        body: String,
        d: Map<String, String>,
        channelId: String,
        headsUp: Boolean
    ) {
        // 탭 시 상세 화면
        val dataJson = try { JSONObject(d as Map<*, *>).toString(2) } catch (_: Throwable) { "{}" }
        val detailIntent = Intent(this, NotificationDetailActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("title", title)
            putExtra("body", body)
            putExtra("data_json", dataJson)
            putExtra("actionUrl", d["actionUrl"])
        }
        val contentPi = PendingIntent.getActivity(
            this, 4003, detailIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // (긴급일 때만) 중지 액션
        val stopIntent = Intent(this, AlarmSoundService::class.java).apply {
            action = AlarmSoundService.ACTION_STOP
        }
        val stopPi = PendingIntent.getService(
            this, 4001, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(contentPi)

        if (channelId == CH_CRITICAL) {
            builder.setCategory(NotificationCompat.CATEGORY_ALARM)
                   .setPriority(if (headsUp) NotificationCompat.PRIORITY_MAX else NotificationCompat.PRIORITY_DEFAULT)
                   .addAction(0, "중지", stopPi)
        } else {
            // 일반 알림은 헤드업을 피하고 채널/시스템 설정에 따름
            builder.setCategory(NotificationCompat.CATEGORY_MESSAGE)
                   .setPriority(NotificationCompat.PRIORITY_DEFAULT)
        }

        d["ticker"]?.let { builder.setTicker(it) }
        NotificationManagerCompat.from(this).notify(notifId, builder.build())
    }

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager


        // 긴급(알람) 채널
        if (nm.getNotificationChannel(CH_CRITICAL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CH_CRITICAL, "Critical Alerts",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "무음/방해금지에도 울릴 수 있는 긴급 알림"
                    setBypassDnd(true)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                }
            )
        }

        // 일반 채널
        if (nm.getNotificationChannel(CH_NORMAL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CH_NORMAL, "General Alerts",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "일반 알림(무음/방해금지를 우회하지 않음)"
                    setBypassDnd(false)
                }
            )
        }
    }

    override fun onNewToken(token: String) {
        Log.i(TAG, "FCM new token: $token")
        super.onNewToken(token)
    }
}
