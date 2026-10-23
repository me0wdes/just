package com.example.day_planner

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.media.AudioManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "day/platform").setMethodCallHandler { call, result ->
            when (call.method) {
                "feedbackAllowed" -> {
                    val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    result.success(audio.ringerMode == AudioManager.RINGER_MODE_NORMAL)
                }
                "hasPackageIdentity" -> result.success(true)
                "openUrl" -> {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url"))))
                    result.success(null)
                }
                "openNotificationSettings" -> {
                    val exact = call.argument<Boolean>("exact") == true
                    val intent = if (exact && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName"))
                    } else {
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    }
                    startActivity(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
