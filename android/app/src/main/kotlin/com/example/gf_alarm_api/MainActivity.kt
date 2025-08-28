package com.example.gf_alarm_api

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.app.AlarmManager
import android.content.Context
import android.provider.Settings

class MainActivity: FlutterActivity() {
    private val chName = "gf_alarm_channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, chName)
            .setMethodCallHandler { call, result ->
                when (call.method) {                   
                    // ★ 추가: 사운드 서비스 제어
                    "startAlarmSound" -> {
                        val svc = Intent(this, AlarmSoundService::class.java)
                        startForegroundService(svc)
                        result.success(true)
                    }
                    "stopAlarmSound" -> {
                        val svc = Intent(this, AlarmSoundService::class.java).apply {
                            action = AlarmSoundService.ACTION_STOP
                        }
                        startService(svc)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
