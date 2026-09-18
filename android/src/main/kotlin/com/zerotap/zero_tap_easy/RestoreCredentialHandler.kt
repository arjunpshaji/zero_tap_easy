package com.zerotap.zero_tap_easy

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CreateRestoreCredentialRequest
import androidx.credentials.CreateRestoreCredentialResponse
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetRestoreCredentialOption
import androidx.credentials.RestoreCredential
import androidx.credentials.exceptions.CreateCredentialCancellationException
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import androidx.credentials.exceptions.restorecredential.CreateRestoreCredentialDomException
import androidx.credentials.exceptions.restorecredential.E2eeUnavailableException

/**
 * Wraps the Credential Manager restore-key calls.
 *
 * Every method here is `suspend` and expects to be called from the main
 * dispatcher, which is what Credential Manager wants.
 */
internal class RestoreCredentialHandler(
    private val context: Context,
) {
    private val credentialManager: CredentialManager by lazy {
        CredentialManager.create(context)
    }

    /**
     * Whether restore keys can be used here.
     *
     * Requires Android 9 (API 28) and Google Play services 24220000 or higher.
     */
    fun isSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        return gmsVersion() >= MIN_GMS_VERSION
    }

    @RequiresApi(Build.VERSION_CODES.P)
    suspend fun createRestoreKey(
        requestJson: String,
        isCloudBackupEnabled: Boolean,
    ): String {
        val request = CreateRestoreCredentialRequest(requestJson, isCloudBackupEnabled)
        try {
            val response = credentialManager.createCredential(context, request)
            val restoreResponse = response as? CreateRestoreCredentialResponse
                ?: throw ZeroTapError(
                    ZeroTapErrorCode.FAILED,
                    "Credential Manager returned ${response.type} rather than a restore credential.",
                )
            return restoreResponse.responseJson
        } catch (e: E2eeUnavailableException) {
            throw ZeroTapError(
                ZeroTapErrorCode.E2EE_UNAVAILABLE,
                "Cloud backup is unavailable: the device needs Google backup enabled " +
                    "and a screen lock set. Retry with isCloudBackupEnabled = false " +
                    "for a local-only key.",
                e,
            )
        } catch (e: CreateRestoreCredentialDomException) {
            throw ZeroTapError(
                ZeroTapErrorCode.INVALID_REQUEST_JSON,
                "requestJson was rejected as WebAuthn: ${e.message}",
                e,
            )
        } catch (e: IllegalArgumentException) {
            throw ZeroTapError(
                ZeroTapErrorCode.INVALID_REQUEST_JSON,
                "requestJson was empty, not valid JSON, or missing a valid user.id: ${e.message}",
                e,
            )
        } catch (e: CreateCredentialCancellationException) {
            throw ZeroTapError(
                ZeroTapErrorCode.CANCELLED,
                "Creating the restore key was cancelled.",
                e,
            )
        } catch (e: CreateCredentialException) {
            throw ZeroTapError(
                ZeroTapErrorCode.FAILED,
                "Creating the restore key failed: ${e.type} ${e.message}",
                e,
            )
        }
    }

    /** Returns the assertion JSON, or null when this device holds no restore key. */
    @RequiresApi(Build.VERSION_CODES.P)
    suspend fun getRestoreKey(requestJson: String): String? {
        // Google forbids chaining GetRestoreCredentialOption with any other
        // CredentialOption, so this request carries exactly one option.
        val request = GetCredentialRequest(listOf(GetRestoreCredentialOption(requestJson)))
        try {
            val response = credentialManager.getCredential(context, request)
            val credential = response.credential as? RestoreCredential
                ?: throw ZeroTapError(
                    ZeroTapErrorCode.FAILED,
                    "Credential Manager returned ${response.credential.type} " +
                        "rather than a restore credential.",
                )
            return credential.authenticationResponseJson
        } catch (e: NoCredentialException) {
            // The ordinary case on a fresh install. Not an error.
            return null
        } catch (e: GetCredentialCancellationException) {
            throw ZeroTapError(
                ZeroTapErrorCode.CANCELLED,
                "Retrieving the restore key was cancelled.",
                e,
            )
        } catch (e: IllegalArgumentException) {
            throw ZeroTapError(
                ZeroTapErrorCode.INVALID_REQUEST_JSON,
                "requestJson was empty or not valid JSON: ${e.message}",
                e,
            )
        } catch (e: GetCredentialException) {
            throw ZeroTapError(
                ZeroTapErrorCode.FAILED,
                "Retrieving the restore key failed: ${e.type} ${e.message}",
                e,
            )
        }
    }

    @RequiresApi(Build.VERSION_CODES.P)
    suspend fun clearRestoreKey() {
        try {
            credentialManager.clearCredentialState(
                ClearCredentialStateRequest(
                    ClearCredentialStateRequest.TYPE_CLEAR_RESTORE_CREDENTIAL,
                ),
            )
        } catch (e: Exception) {
            throw ZeroTapError(
                ZeroTapErrorCode.FAILED,
                "Clearing the restore key failed: ${e.message}",
                e,
            )
        }
    }

    /**
     * The installed Google Play services version code, or 0 when it is absent.
     *
     * Read straight from the package manager rather than via play-services-base,
     * so this module keeps a single dependency. Requires the `<queries>` entry
     * in the plugin manifest to be visible on API 30 and above.
     */
    private fun gmsVersion(): Long = try {
        val info = context.packageManager.getPackageInfo(GMS_PACKAGE, 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
    } catch (e: PackageManager.NameNotFoundException) {
        0L
    }

    private companion object {
        const val GMS_PACKAGE = "com.google.android.gms"

        /** The minimum Play services core version that supports restore keys. */
        const val MIN_GMS_VERSION = 24220000L
    }
}

/** Error codes shared with the Dart side. Keep in sync with `ZeroTapErrorCode` in Dart. */
internal object ZeroTapErrorCode {
    const val UNSUPPORTED = "UNSUPPORTED"
    const val E2EE_UNAVAILABLE = "E2EE_UNAVAILABLE"
    const val INVALID_REQUEST_JSON = "INVALID_REQUEST_JSON"
    const val CANCELLED = "CANCELLED"
    const val FAILED = "FAILED"
}

/** An error carrying a [ZeroTapErrorCode] across the method channel. */
internal class ZeroTapError(
    val code: String,
    override val message: String,
    cause: Throwable? = null,
) : Exception(message, cause)
