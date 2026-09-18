package com.zerotap.zero_tap_easy

import android.app.Activity
import android.content.Context
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Bridges the Dart API to Credential Manager's restore-key calls.
 *
 * Credential Manager wants an Activity context, so the plugin holds the
 * Activity while attached and falls back to the application context otherwise —
 * the restore-key operations are silent and have no UI, so both work.
 */
class ZeroTapEasyPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context
    private var activity: Activity? = null
    private var scope: CoroutineScope? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope?.cancel()
        scope = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        val handler = RestoreCredentialHandler(activity ?: applicationContext)

        if (call.method == "isSupported") {
            result.success(handler.isSupported())
            return
        }

        if (!handler.isSupported()) {
            result.error(
                ZeroTapErrorCode.UNSUPPORTED,
                "Restore keys need Android 9 (API 28) or higher with Google Play " +
                    "services 24220000 or higher. This device has API " +
                    "${Build.VERSION.SDK_INT}.",
                null,
            )
            return
        }

        val currentScope = scope
        if (currentScope == null) {
            result.error(
                ZeroTapErrorCode.FAILED,
                "The plugin is detached from the Flutter engine.",
                null,
            )
            return
        }

        currentScope.launch {
            try {
                when (call.method) {
                    "createRestoreKey" -> {
                        val requestJson = call.requiredString("requestJson", result) ?: return@launch
                        val isCloudBackupEnabled =
                            call.argument<Boolean>("isCloudBackupEnabled") ?: true
                        result.success(
                            handler.createRestoreKey(requestJson, isCloudBackupEnabled),
                        )
                    }

                    "getRestoreKey" -> {
                        val requestJson = call.requiredString("requestJson", result) ?: return@launch
                        // null here means "no restore key on this device", which
                        // the Dart side surfaces as a null return, not an error.
                        result.success(handler.getRestoreKey(requestJson))
                    }

                    "clearRestoreKey" -> {
                        handler.clearRestoreKey()
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            } catch (e: ZeroTapError) {
                result.error(e.code, e.message, e.cause?.toString())
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                result.error(ZeroTapErrorCode.FAILED, e.message ?: e.toString(), null)
            }
        }
    }

    private fun MethodCall.requiredString(
        name: String,
        result: Result,
    ): String? {
        val value = argument<String>(name)
        if (value.isNullOrEmpty()) {
            result.error(
                ZeroTapErrorCode.INVALID_REQUEST_JSON,
                "Missing required argument '$name'.",
                null,
            )
            return null
        }
        return value
    }

    private companion object {
        const val CHANNEL_NAME = "zero_tap_easy"
    }
}
