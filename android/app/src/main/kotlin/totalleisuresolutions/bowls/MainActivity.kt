package totalleisuresolutions.bowls

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val passwords = SavedLoginBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "bowls/saved_login").setMethodCallHandler(passwords::handle)
    }
}
