package com.example.raspisanie.notifications

import android.util.Log
import com.example.raspisanie.data.PreferencesManager
import com.example.raspisanie.data.ScheduleNotificationManager
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class ScheduleFirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        try {
            ScheduleNotificationManager.handleRemoteMessage(applicationContext, remoteMessage)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to handle remote message: ${e.message}", e)
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        try {
            PreferencesManager(applicationContext).fcmToken = token
            Log.d(TAG, "New FCM token: $token")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to persist FCM token: ${e.message}", e)
        }
    }

    companion object {
        private const val TAG = "ScheduleFcmService"
    }
}
