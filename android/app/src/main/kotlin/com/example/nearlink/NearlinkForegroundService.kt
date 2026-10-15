package com.example.nearlink

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Keeps the process alive while Nearlink is minimised.
 *
 * Android freezes ordinary backgrounded processes, which stops the receiving
 * server, mDNS discovery and clipboard sync. A foreground service with a
 * persistent notification is the supported way to stay alive.
 */
class NearlinkForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "nearlink_receive"
        private const val NOTIFICATION_ID = 4201
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "Nearlink"
        val text = intent?.getStringExtra("text") ?: "Ready to receive"

        createChannel()
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

        startForeground(NOTIFICATION_ID, notification)
        return START_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Receiving",
                    NotificationManager.IMPORTANCE_LOW
                )
                channel.description =
                    "Keeps Nearlink able to receive while it is minimised"
                manager.createNotificationChannel(channel)
            }
        }
    }
}
