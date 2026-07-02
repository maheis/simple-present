package be.heister.simplepresent

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
	private val ACTION_TASK_DONE = "be.heister.simplepresent.ACTION_TASK_DONE"
	private val ACTION_TASK_IN_PROGRESS = "be.heister.simplepresent.ACTION_TASK_IN_PROGRESS"
	private val ACTION_OPEN_FROM_WIDGET = "be.heister.simplepresent.ACTION_OPEN_FROM_WIDGET"
	private val EXTRA_TASK_ID = "task_id"
	private val EXTRA_NOTIFICATION_ID = "notification_id"
	private val PERMISSION_REQUEST_CODE = 1001
	private var pendingTitle: String? = null
	private var pendingBody: String? = null
	private var pendingTaskId: String? = null
	private var pendingPermissionResult: MethodChannel.Result? = null
	private var windowChannel: MethodChannel? = null
	private val pendingTaskActions = mutableListOf<Pair<String, String>>()
	private val pendingOpenTaskIds = mutableListOf<String>()

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "simple_present/window")
		windowChannel = channel
		channel
			.setMethodCallHandler { call: MethodCall, result ->
				when (call.method) {
					"notify" -> {
						val args = call.arguments as? Map<*, *>
						val title = args?.get("title") as? String ?: "SimplePresent"
						val body = args?.get("body") as? String ?: ""
						val taskId = args?.get("taskId") as? String
						showNotification(title, body, taskId)
						result.success(null)
					}
					"bringToFront" -> {
						bringAppToFront()
						result.success(null)
					}
					"refreshTodayWidget" -> {
						refreshTodayWidget()
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
		flushPendingTaskActions()
		flushPendingOpenTasks()
		handleIntent(intent)
	}

	private fun ensureChannel() {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			val name = "SimplePresent notifications"
			val descriptionText = "Notifications for SimplePresent reminders"
			val importance = NotificationManager.IMPORTANCE_DEFAULT
			val channel = NotificationChannel(CHANNEL_ID, name, importance)
			channel.description = descriptionText

			// Ensure the notification sound uses notification usage so it does not
			// interrupt ongoing media playback. Use the system default notification URI.
			try {
				val defaultSound = android.provider.Settings.System.DEFAULT_NOTIFICATION_URI
				val audioAttributes = android.media.AudioAttributes.Builder()
					.setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION)
					.setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
					.build()
				channel.setSound(defaultSound, audioAttributes)
			} catch (e: Exception) {
				// fallback: ignore if audio attributes aren't available for some reason
			}
			val notificationManager: NotificationManager =
				getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
			notificationManager.createNotificationChannel(channel)
		}
	}

	private fun showNotification(title: String, body: String, taskId: String? = null) {
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
				pendingTaskId = taskId
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

		val notificationId = System.currentTimeMillis().toInt()
		val pendingIntent: PendingIntent = PendingIntent.getActivity(
			this,
			0,
			intent,
			PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
		)

		val builder = NotificationCompat.Builder(this, CHANNEL_ID)
			.setSmallIcon(R.drawable.ic_stat_notify)
			.setColor(ContextCompat.getColor(this, R.color.ic_notification_color))
			.setContentTitle(title)
			.setContentText(body)
			.setPriority(NotificationCompat.PRIORITY_DEFAULT)
			.setContentIntent(pendingIntent)
			.setAutoCancel(true)

		val useTaskId = taskId?.trim().orEmpty()
		if (useTaskId.isNotEmpty()) {
			val doneIntent = Intent(this, MainActivity::class.java).apply {
				action = ACTION_TASK_DONE
				flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
				putExtra(EXTRA_TASK_ID, useTaskId)
				putExtra(EXTRA_NOTIFICATION_ID, notificationId)
			}
			val donePendingIntent = PendingIntent.getActivity(
				this,
				notificationId + 1,
				doneIntent,
				PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
			)

			val inProgressIntent = Intent(this, MainActivity::class.java).apply {
				action = ACTION_TASK_IN_PROGRESS
				flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
				putExtra(EXTRA_TASK_ID, useTaskId)
				putExtra(EXTRA_NOTIFICATION_ID, notificationId)
			}
			val inProgressPendingIntent = PendingIntent.getActivity(
				this,
				notificationId + 2,
				inProgressIntent,
				PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
			)

			builder
				.addAction(0, "erledigt", donePendingIntent)
				.addAction(0, "in arbeit", inProgressPendingIntent)
		}

		with(NotificationManagerCompat.from(this)) {
			notify(notificationId, builder.build())
		}
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		setIntent(intent)
		handleIntent(intent)
	}

	private fun handleIntent(intent: Intent?) {
		val action = intent?.action ?: return
		if (
			action != ACTION_TASK_DONE &&
			action != ACTION_TASK_IN_PROGRESS &&
			action != ACTION_OPEN_FROM_WIDGET
		) return

		val taskId = intent.getStringExtra(EXTRA_TASK_ID)?.trim().orEmpty()
		if (taskId.isEmpty()) return

		if (action == ACTION_OPEN_FROM_WIDGET) {
			dispatchOpenTask(taskId)
			return
		}

		val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)
		if (notificationId > 0) {
			try {
				NotificationManagerCompat.from(this).cancel(notificationId)
			} catch (_: Exception) {}
		}

		val flutterAction = if (action == ACTION_TASK_DONE) "done" else "in_progress"
		dispatchTaskAction(taskId, flutterAction)
	}

	private fun dispatchTaskAction(taskId: String, action: String) {
		val channel = windowChannel
		if (channel == null) {
			pendingTaskActions.add(Pair(taskId, action))
			return
		}
		try {
			channel.invokeMethod(
				"notificationTaskAction",
				mapOf("taskId" to taskId, "action" to action)
			)
			refreshTodayWidget()
		} catch (_: Exception) {
			pendingTaskActions.add(Pair(taskId, action))
		}
	}

	private fun refreshTodayWidget() {
		try {
			val intent = Intent(this, TodayWidgetProvider::class.java).apply {
				action = TodayWidgetProvider.ACTION_REFRESH_WIDGET
			}
			sendBroadcast(intent)
		} catch (_: Exception) {}
	}

	private fun flushPendingTaskActions() {
		if (pendingTaskActions.isEmpty()) return
		val channel = windowChannel ?: return
		val queued = pendingTaskActions.toList()
		pendingTaskActions.clear()
		for (item in queued) {
			try {
				channel.invokeMethod(
					"notificationTaskAction",
					mapOf("taskId" to item.first, "action" to item.second)
				)
			} catch (_: Exception) {
				pendingTaskActions.add(item)
			}
		}
	}

	private fun dispatchOpenTask(taskId: String) {
		val channel = windowChannel
		if (channel == null) {
			pendingOpenTaskIds.add(taskId)
			return
		}
		try {
			channel.invokeMethod(
				"openTaskFromWidget",
				mapOf("taskId" to taskId)
			)
		} catch (_: Exception) {
			pendingOpenTaskIds.add(taskId)
		}
	}

	private fun flushPendingOpenTasks() {
		if (pendingOpenTaskIds.isEmpty()) return
		val channel = windowChannel ?: return
		val queued = pendingOpenTaskIds.toList()
		pendingOpenTaskIds.clear()
		for (taskId in queued) {
			try {
				channel.invokeMethod(
					"openTaskFromWidget",
					mapOf("taskId" to taskId)
				)
			} catch (_: Exception) {
				pendingOpenTaskIds.add(taskId)
			}
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
					showNotification(t ?: "SimplePresent", b ?: "", pendingTaskId)
				}
			}
			pendingTitle = null
			pendingBody = null
			pendingTaskId = null
		}
	}
}
