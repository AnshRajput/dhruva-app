package tech.appuinside.dhruva.connectors

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Channel `app.dhruva/connectors`: the native half of the connectors (Dart:
 * lib/data/connectors/system_sources.dart). A plugin so the WorkManager
 * background engine gets it too; calls that need an Activity (permission
 * prompt, folder picker) answer `no_activity` there and the Dart side treats
 * that as "needs the app open".
 *
 * Methods: calendar.permission | calendar.request | calendar.events,
 * permission.asked | markAsked | rationale (calendar, contacts),
 * app.settings, apps.launch, folder.pick | reachable | list | fetch | open |
 * release,
 * notifications.granted | settings | capture | excluded | queueDir,
 * power.charging.
 *
 * Second channel `app.dhruva/model_import` (sideloading a GGUF): pick (SAF
 * ACTION_OPEN_DOCUMENT) | copy (streamed by [ModelImport]; reports `progress`
 * back to Dart) | cancel.
 */
class DhruvaConnectorsPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var pendingPick: MethodChannel.Result? = null
    private var pendingCalendar: MethodChannel.Result? = null

    private lateinit var importChannel: MethodChannel
    private var pendingModelPick: MethodChannel.Result? = null
    @Volatile private var pickedModelUri: Uri? = null
    private var importCancelled = AtomicBoolean(false)

    // ---- FlutterPlugin / ActivityAware ----------------------------------------

    override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
        context = b.applicationContext
        channel = MethodChannel(b.binaryMessenger, "app.dhruva/connectors")
        channel.setMethodCallHandler(this)
        importChannel = MethodChannel(b.binaryMessenger, "app.dhruva/model_import")
        importChannel.setMethodCallHandler(::onImportCall)
    }

    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        importChannel.setMethodCallHandler(null)
        worker.shutdown()
    }

    override fun onAttachedToActivity(b: ActivityPluginBinding) = attach(b)
    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) = attach(b)
    override fun onDetachedFromActivityForConfigChanges() = detach()
    override fun onDetachedFromActivity() = detach()

    private fun attach(b: ActivityPluginBinding) {
        binding = b
        activity = b.activity
        b.addActivityResultListener(this)
        b.addRequestPermissionsResultListener(this)
    }

    private fun detach() {
        binding?.removeActivityResultListener(this)
        binding?.removeRequestPermissionsResultListener(this)
        binding = null
        activity = null
    }

    // ---- dispatch ---------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "calendar.permission" -> result.success(calendarPermission())
                "calendar.request" -> requestCalendar(result)
                "permission.asked" -> result.success(ConnectorPrefs.asked(context, permissionName(call)))
                "permission.markAsked" -> {
                    ConnectorPrefs.setAsked(context, permissionName(call))
                    result.success(null)
                }
                "permission.rationale" -> result.success(rationale(permissionName(call)))
                "calendar.events" -> background(result) {
                    CalendarReader.events(
                        context,
                        (call.argument<Number>("from") ?: 0).toLong(),
                        (call.argument<Number>("to") ?: 0).toLong(),
                    )
                }
                "app.settings" -> {
                    startSettings(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}")),
                    )
                    result.success(null)
                }

                "folder.pick" -> pickFolder(result)
                "folder.reachable" -> background(result) {
                    FolderAccess.reachable(context, FolderAccess.treeUri(requireArg(call, "id")))
                }
                "folder.list" -> background(result) {
                    FolderAccess.list(
                        context,
                        FolderAccess.treeUri(requireArg(call, "id")),
                        (call.argument<Number>("maxFiles") ?: 2000).toInt().coerceIn(1, 2000),
                    )
                }
                "folder.fetch" -> background(result) {
                    FolderAccess.fetch(
                        context,
                        FolderAccess.treeUri(requireArg(call, "id")),
                        requireArg(call, "entryId"),
                        requireArg(call, "dest"),
                        (call.argument<Number>("maxBytes") ?: 0).toLong(),
                    )
                    null
                }
                "folder.open" -> {
                    FolderAccess.open(
                        context,
                        activity,
                        FolderAccess.treeUri(requireArg(call, "id")),
                        requireArg(call, "entryId"),
                    )
                    result.success(true)
                }
                "apps.launch" -> result.success(launchApp(requireArg(call, "package")))
                "folder.release" -> {
                    FolderAccess.release(context, FolderAccess.treeUri(requireArg(call, "id")))
                    result.success(null)
                }

                "notifications.granted" -> result.success(notificationAccessGranted())
                "notifications.settings" -> {
                    openNotificationAccessSettings()
                    result.success(null)
                }
                "notifications.capture" -> {
                    ConnectorPrefs.setCapture(context, call.argument<Boolean>("enabled") == true)
                    result.success(null)
                }
                "notifications.excluded" -> {
                    ConnectorPrefs.setExcluded(context, call.argument<List<String>>("packages").orEmpty())
                    result.success(null)
                }
                "notifications.queueDir" -> result.success(NotificationQueueWriter.directory(context).absolutePath)

                "power.charging" -> result.success(isCharging())
                else -> result.notImplemented()
            }
        } catch (e: FolderError) {
            result.error(e.code, e.message, null)
        } catch (e: Exception) {
            result.error("failed", e.message ?: e.javaClass.simpleName, null)
        }
    }

    private fun requireArg(call: MethodCall, key: String): String =
        call.argument<String>(key)?.takeIf { it.isNotEmpty() }
            ?: throw FolderError("bad_args", "Missing $key.")

    /** Runs [block] off the main thread and answers on the main thread. */
    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            try {
                val v = block()
                main.post { result.success(v) }
            } catch (e: FolderError) {
                main.post { result.error(e.code, e.message, null) }
            } catch (e: SecurityException) {
                main.post { result.error("denied", "Access was revoked.", null) }
            } catch (e: Exception) {
                main.post { result.error("failed", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    // ---- calendar (READ_CALENDAR only) ----------------------------------------------

    /** Raw grant state. Whether a denial is final is Dart's call (PermissionGate). */
    private fun calendarPermission(): String =
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALENDAR) ==
            PackageManager.PERMISSION_GRANTED
        ) "granted" else "denied"

    private fun permissionName(call: MethodCall): String {
        val n = requireArg(call, "name")
        if (n != "calendar" && n != "contacts") throw IllegalArgumentException("Unknown permission: $n")
        return n
    }

    /**
     * ActivityCompat.shouldShowRequestPermissionRationale: true after a first
     * Deny (the system will prompt again), false when never asked or when the
     * user denied for good. False too with no Activity (background engine).
     */
    private fun rationale(name: String): Boolean {
        val a = activity ?: return false
        val perm = if (name == "calendar") Manifest.permission.READ_CALENDAR else Manifest.permission.READ_CONTACTS
        return ActivityCompat.shouldShowRequestPermissionRationale(a, perm)
    }

    private fun requestCalendar(result: MethodChannel.Result) {
        val a = activity
        if (a == null) {
            result.error("no_activity", "Open the app to grant calendar access.", null)
            return
        }
        if (calendarPermission() == "granted") {
            result.success("granted")
            return
        }
        pendingCalendar?.error("superseded", "Another request started.", null)
        pendingCalendar = result
        ActivityCompat.requestPermissions(a, arrayOf(Manifest.permission.READ_CALENDAR), REQ_CALENDAR)
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray): Boolean {
        if (code != REQ_CALENDAR) return false
        val r = pendingCalendar ?: return true
        pendingCalendar = null
        r.success(if (results.isNotEmpty() && results[0] == PackageManager.PERMISSION_GRANTED) "granted" else "denied")
        return true
    }

    // ---- folder picker -----------------------------------------------------------------

    private fun pickFolder(result: MethodChannel.Result) {
        val a = activity
        if (a == null) {
            result.error("no_activity", "Open the app to choose a folder.", null)
            return
        }
        pendingPick?.success(null)
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
        )
        try {
            a.startActivityForResult(intent, REQ_PICK_FOLDER)
        } catch (e: Exception) {
            pendingPick = null
            result.error("no_picker", "This phone has no folder picker.", null)
        }
    }

    override fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code == REQ_PICK_MODEL) return onModelPicked(resultCode, data)
        if (code != REQ_PICK_FOLDER) return false
        val r = pendingPick ?: return true
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            r.success(null) // cancelled
            return true
        }
        worker.execute {
            try {
                FolderAccess.takeReadGrant(context, uri)
                val name = FolderAccess.displayName(context, uri)
                main.post { r.success(mapOf("id" to uri.toString(), "name" to name)) }
            } catch (e: Exception) {
                main.post { r.error("failed", "Could not keep access to that folder.", null) }
            }
        }
        return true
    }

    // ---- model import (stream-copy; never loads the file into memory) --------------------

    private fun onImportCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "pick" -> pickModel(result)
                "copy" -> copyModel(call, result)
                "cancel" -> {
                    importCancelled.set(true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: FolderError) {
            result.error(e.code, e.message, null)
        } catch (e: Exception) {
            result.error("failed", e.message ?: e.javaClass.simpleName, null)
        }
    }

    private fun pickModel(result: MethodChannel.Result) {
        val a = activity
        if (a == null) {
            result.error("no_activity", "Open the app to choose a file.", null)
            return
        }
        pendingModelPick?.success(null)
        pendingModelPick = result
        // GGUF has no registered MIME type, so offer everything; Dart rejects non-.gguf names.
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*").addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
        )
        try {
            a.startActivityForResult(intent, REQ_PICK_MODEL)
        } catch (e: Exception) {
            pendingModelPick = null
            result.error("no_picker", "This phone has no file picker.", null)
        }
    }

    private fun copyModel(call: MethodCall, result: MethodChannel.Result) {
        val uri = pickedModelUri
        if (uri == null || uri.toString() != requireArg(call, "uri")) {
            result.error("unreadable", "Pick the file again.", null)
            return
        }
        val dest = File(requireArg(call, "dest"))
        importCancelled = AtomicBoolean(false)
        val cancelled = importCancelled
        worker.execute {
            try {
                val n = ModelImport.copy(context, uri, dest, cancelled) { copied, total ->
                    main.post { importChannel.invokeMethod("progress", mapOf("copied" to copied, "total" to total)) }
                }
                main.post { result.success(n) }
            } catch (e: ImportError) {
                main.post { result.error(e.code, e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("failed", e.message ?: e.javaClass.simpleName, null) }
            } finally {
                ModelImport.release(context, uri)
                if (pickedModelUri == uri) pickedModelUri = null
            }
        }
    }

    private fun onModelPicked(resultCode: Int, data: Intent?): Boolean {
        val r = pendingModelPick ?: return true
        pendingModelPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            r.success(null) // cancelled
            return true
        }
        worker.execute {
            try {
                ModelImport.keepGrant(context, uri)
                val (name, size) = ModelImport.describe(context, uri)
                pickedModelUri = uri
                main.post { r.success(mapOf("uri" to uri.toString(), "name" to name, "size" to size)) }
            } catch (e: Exception) {
                main.post { r.error("failed", "Could not read that file.", null) }
            }
        }
        return true
    }

    // ---- notification access ----------------------------------------------------------------

    private fun notificationAccessGranted(): Boolean =
        NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName)

    private fun openNotificationAccessSettings() {
        val component = ComponentName(context, NotificationCaptureService::class.java)
        val detail = Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
            .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, component.flattenToString())
        val general = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                startSettings(detail)
                return
            } catch (_: Exception) {
            }
        }
        startSettings(general)
    }

    /**
     * Opens the launcher activity of [pkg] (the app a notification came from).
     * False when the app is gone or has no launcher entry; never throws for
     * that, so the UI can say so.
     */
    private fun launchApp(pkg: String): Boolean {
        val intent = context.packageManager.getLaunchIntentForPackage(pkg) ?: return false
        return try {
            val a = activity
            if (a != null) a.startActivity(intent)
            else context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun startSettings(intent: Intent) {
        val a = activity
        if (a != null) a.startActivity(intent)
        else context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    // ---- power --------------------------------------------------------------------------------------

    private fun isCharging(): Boolean {
        val i = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val status = i?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        return status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
    }

    private companion object {
        const val REQ_CALENDAR = 4101
        const val REQ_PICK_FOLDER = 4102
        const val REQ_PICK_MODEL = 4103
    }
}
