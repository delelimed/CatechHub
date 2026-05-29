package com.delelimed.registro_catechismo

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.delelimed.registro_catechismo.BuildConfig

class MainActivity : FlutterFragmentActivity() {
    private val securityChannel = "com.delelimed.registro_catechismo/security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Enforce secure screenshots policy based on build type:
        // - Debug: allow screenshots (clear FLAG_SECURE)
        // - Release: prohibit screenshots (set FLAG_SECURE)
        runOnUiThread {
            if (BuildConfig.DEBUG) {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                window.setFlags(
                    WindowManager.LayoutParams.FLAG_SECURE,
                    WindowManager.LayoutParams.FLAG_SECURE,
                )
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, securityChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecureFlag" -> {
                        val requested = call.argument<Boolean>("enabled") ?: false
                        // In release builds always keep FLAG_SECURE enabled (no screenshots).
                        val enabled = if (BuildConfig.DEBUG) requested else true
                        runOnUiThread {
                            if (enabled) {
                                window.setFlags(
                                    WindowManager.LayoutParams.FLAG_SECURE,
                                    WindowManager.LayoutParams.FLAG_SECURE,
                                )
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}