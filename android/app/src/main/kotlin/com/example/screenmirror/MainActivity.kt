package com.example.screenmirror

import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.screenmirror/channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Register Platform View Factory
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.example.screenmirror/surface_view",
            object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
                    return MirrorSurfaceView(context)
                }
            }
        )

        // 2. Set up Method Channel
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        UsbReceiver.methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> {
                    val mode = call.argument<String>("connectionMode") ?: "adbReverse"
                    
                    // Start Foreground Service
                    val serviceIntent = Intent(this, ForegroundService::class.java)
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }
                    
                    UsbReceiver.startListening(mode) { status ->
                        // Callback updates handled inside UsbReceiver
                    }
                    result.success(true)
                }
                "stopListening" -> {
                    UsbReceiver.stopListening()
                    
                    // Stop Foreground Service
                    val serviceIntent = Intent(this, ForegroundService::class.java).apply {
                        action = "STOP"
                    }
                    startService(serviceIntent)
                    
                    result.success(true)
                }
                "getDisplays" -> {
                    // macOS only helper
                    result.success(emptyList<Map<String, Any>>())
                }
                "getDevices" -> {
                    // macOS only helper
                    result.success(emptyList<Map<String, Any>>())
                }
                "runAdbCommand" -> {
                    // macOS only helper
                    result.success(false)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        requestNotificationPermission()
    }

    private fun requestNotificationPermission() {
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
            }
        }
    }

    override fun onDestroy() {
        UsbReceiver.stopListening()
        val serviceIntent = Intent(this, ForegroundService::class.java).apply {
            action = "STOP"
        }
        startService(serviceIntent)
        super.onDestroy()
    }
}
