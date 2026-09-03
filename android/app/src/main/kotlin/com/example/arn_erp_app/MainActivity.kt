package com.example.arn_erp_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "motus/native_location_service"
        private const val NOTIFICATION_PERMISSION_REQUEST = 4701
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                NOTIFICATION_PERMISSION_REQUEST
                            )
                        }

                        val intent = Intent(this, MotusLocationService::class.java).apply {
                            putExtra("supabaseUrl", call.argument<String>("supabaseUrl") ?: "")
                            putExtra("apiKey", call.argument<String>("apiKey") ?: "")
                            putExtra("accessToken", call.argument<String>("accessToken") ?: "")
                            putExtra("refreshToken", call.argument<String>("refreshToken") ?: "")
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (error: Throwable) {
                        result.error(
                            "MOTUS_LOCATION_START",
                            error.message ?: "Konum servisi başlatılamadı.",
                            null
                        )
                    }
                }

                "stop" -> {
                    stopService(Intent(this, MotusLocationService::class.java))
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }
}
