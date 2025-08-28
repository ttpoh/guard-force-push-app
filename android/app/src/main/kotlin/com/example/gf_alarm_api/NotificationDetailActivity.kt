package com.example.gf_alarm_api

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class NotificationDetailActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_notification_detail)

        val title = intent.getStringExtra("title") ?: "알림"
        val body = intent.getStringExtra("body") ?: ""
        val dataJson = intent.getStringExtra("data_json") ?: "{}"
        val actionUrl = intent.getStringExtra("actionUrl")

        findViewById<TextView>(R.id.tvTitle).text = title
        findViewById<TextView>(R.id.tvBody).text = body
        findViewById<TextView>(R.id.tvJson).text = dataJson

        // 소리 중지 버튼
        findViewById<Button>(R.id.btnStop).setOnClickListener {
            val stop = Intent(this, AlarmSoundService::class.java).apply {
                action = AlarmSoundService.ACTION_STOP
            }
            startService(stop)
            finish()
        }

        // 링크 열기 (actionUrl 있으면 보이기)
        val btnOpen = findViewById<Button>(R.id.btnOpenLink)
        if (!actionUrl.isNullOrBlank()) {
            btnOpen.setOnClickListener {
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(actionUrl)))
            }
            btnOpen.visibility = android.view.View.VISIBLE
        } else {
            btnOpen.visibility = android.view.View.GONE
        }

        // 닫기
        findViewById<Button>(R.id.btnClose).setOnClickListener { finish() }
    }
}
