package de.maheis.simplepresent

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.Manifest
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val CHANNEL_ID = "simple_present_channel"
	private val PERMISSION_REQUEST_CODE = 1001
	private var pendingTitle: String? = null
	private var pendingBody: String? = null
	private var pendingPermissionResult: MethodChannel.Result? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "simple_present/window")
			.setMethodCallHandler { call: MethodCall, result ->
				when (call.method) {
					"notify" -> {
						val args = call.arguments as? Map<*, *>
						val title = args?.get("title") as? String ?: "SimplePresent"
						val body = args?.get("body") as? String ?: ""
						showNotification(title, body)
						result.success(null)
					}
					"bringToFront" -> {
						bringAppToFront()
						result.success(null)
					}
					else -> result.notImplemented()
				}
			}

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "simple_present/permissions")
			.setMethodCallHandler { call: MethodCall, result ->
				when (call.method) {
					"requestNotificationPermission" -> {
						resultNotificationPermission(result)
					}
					else -> result.notImplemented()
				}
			}

		// Cloud Sync HTTP client channel removed - not needed with proper Apache config
	}

	private fun ensureChannel() {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			val name = "SimplePresent notifications"
			val descriptionText = "Notifications for SimplePresent reminders"
			val importance = NotificationManager.IMPORTANCE_DEFAULT
			val channel = NotificationChannel(CHANNEL_ID, name, importance)
			channel.description = descriptionText
			val notificationManager: NotificationManager =
				getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
			notificationManager.createNotificationChannel(channel)
		}
	}

	private fun showNotification(title: String, body: String) {
		// On Android 13+ we need runtime permission to post notifications
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
			val granted = ContextCompat.checkSelfPermission(
				this,
				Manifest.permission.POST_NOTIFICATIONS
			) == android.content.pm.PackageManager.PERMISSION_GRANTED
			if (!granted) {
				// store pending payload so we can show it after permission granted
				pendingTitle = title
				pendingBody = body
				ActivityCompat.requestPermissions(
					this,
					arrayOf(Manifest.permission.POST_NOTIFICATIONS),
					PERMISSION_REQUEST_CODE
				)
				// Permission requested; will show when user responds.
				return
			}
		}
		ensureChannel()

		val intent = Intent(this, MainActivity::class.java).apply {
			flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
		}


		val pendingIntent: PendingIntent = PendingIntent.getActivity(
			this,
			0,
			intent,
			PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
		)

		val builder = NotificationCompat.Builder(this, CHANNEL_ID)
			.setSmallIcon(R.drawable.ic_stat_notify)
			.setContentTitle(title)
			.setContentText(body)
			.setPriority(NotificationCompat.PRIORITY_DEFAULT)
			.setContentIntent(pendingIntent)
			.setAutoCancel(true)

		with(NotificationManagerCompat.from(this)) {
			notify(System.currentTimeMillis().toInt(), builder.build())
		}
	}

	private fun bringAppToFront() {
		val intent = Intent(this, MainActivity::class.java)
		intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
		startActivity(intent)
	}

	private fun resultNotificationPermission(result: MethodChannel.Result) {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
			result.success(true)
			return
		}

		val granted = ContextCompat.checkSelfPermission(
			this,
			Manifest.permission.POST_NOTIFICATIONS
		) == android.content.pm.PackageManager.PERMISSION_GRANTED

		if (granted) {
			result.success(true)
			return
		}

		pendingPermissionResult = result
		ActivityCompat.requestPermissions(
			this,
			arrayOf(Manifest.permission.POST_NOTIFICATIONS),
			PERMISSION_REQUEST_CODE
		)
	}

	override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
		super.onRequestPermissionsResult(requestCode, permissions, grantResults)
		if (requestCode == PERMISSION_REQUEST_CODE) {
			val granted = grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED

			pendingPermissionResult?.success(granted)
			pendingPermissionResult = null

			if (granted) {
				val t = pendingTitle
				val b = pendingBody
				if (t != null || b != null) {
					showNotification(t ?: "SimplePresent", b ?: "")
				}
			}
			pendingTitle = null
			pendingBody = null
		}
	}
}
