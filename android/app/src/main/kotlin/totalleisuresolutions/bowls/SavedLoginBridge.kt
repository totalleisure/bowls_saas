package totalleisuresolutions.bowls

import android.os.CancellationSignal
import androidx.core.content.ContextCompat
import androidx.credentials.CreateCredentialResponse
import androidx.credentials.CreatePasswordRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.GetPasswordOption
import androidx.credentials.PasswordCredential
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Delegates password storage and selection to the user's system provider.
 * No credentials are logged or persisted by this bridge. Selection never submits login.
 */
class SavedLoginBridge(private val activity: FlutterFragmentActivity) {
    private val manager = CredentialManager.create(activity)
    private var busy = false
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "get" && call.method != "save") {
            result.notImplemented()
            return
        }
        if (busy) {
            result.error("busy", "A password-manager action is already open.", null)
            return
        }
        busy = true
        try {
            if (call.method == "get") {
                manager.getCredentialAsync(activity,
                    GetCredentialRequest(listOf(GetPasswordOption(isAutoSelectAllowed = false))),
                    CancellationSignal(), ContextCompat.getMainExecutor(activity),
                    object : CredentialManagerCallback<GetCredentialResponse, GetCredentialException> {
                        override fun onResult(response: GetCredentialResponse) {
                            busy = false
                            val credential = response.credential
                            if (credential is PasswordCredential) {
                                result.success(mapOf("identifier" to credential.id, "password" to credential.password))
                            } else result.error("unsupported", "Choose a saved password login.", null)
                        }
                        override fun onError(error: GetCredentialException) {
                            busy = false
                            val code = when (error) {
                                is GetCredentialCancellationException -> "cancelled"
                                is NoCredentialException -> "no_credentials"
                                else -> "unavailable"
                            }
                            result.error(code, "Saved login selection was cancelled or unavailable.", null)
                        }
                    })
            } else {
                val identifier = requireNotNull(call.argument<String>("identifier"))
                val password = requireNotNull(call.argument<String>("password"))
                require(identifier.isNotBlank() && password.isNotEmpty())
                manager.createCredentialAsync(activity, CreatePasswordRequest(identifier, password),
                    CancellationSignal(), ContextCompat.getMainExecutor(activity),
                    object : CredentialManagerCallback<CreateCredentialResponse, CreateCredentialException> {
                        override fun onResult(response: CreateCredentialResponse) {
                            busy = false
                            result.success(true)
                        }
                        override fun onError(error: CreateCredentialException) {
                            busy = false
                            // Declining or being unable to save must never invalidate successful login.
                            result.success(false)
                        }
                    })
            }
        } catch (_: Exception) {
            busy = false
            result.error("unavailable", "Your password manager is unavailable. You can enter your details manually.", null)
        }
    }
}
