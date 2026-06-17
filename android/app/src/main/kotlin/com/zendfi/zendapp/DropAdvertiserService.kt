package com.zendfi.zendapp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.util.UUID

/**
 * DropAdvertiserService — Android Foreground Service for Zend Drop BLE advertising.
 *
 * Broadcasts a 28-byte manufacturer-specific BLE advertisement for proximity discovery
 * and exposes a GATT server so the Sender can retrieve the full signed beacon payload.
 *
 * Advertisement packet layout (28 bytes):
 *   Bytes  0– 3 : AppID  (0x5A 0x45 0x4E 0x44 — "ZEND")
 *   Bytes  4–11 : Nonce  (first 8 bytes of nonce UUID hex, big-endian)
 *   Bytes 12–15 : Timestamp (Unix seconds, big-endian uint32)
 *   Bytes 16–27 : Sig hash (first 12 bytes of HMAC-SHA256 output, hex-decoded)
 *
 * GATT server:
 *   Service UUID        : 12345678-1234-1234-1234-123456789abc
 *   Characteristic UUID : abcdefab-cdef-abcd-efab-cdefabcdefab  (READ)
 *   Value               : UTF-8 JSON bytes of the full beacon payload
 *
 * MethodChannel: "com.zendfi.app/drop_advertiser"
 *   startAdvertising(Map payload) — starts BLE advertising with the given beacon
 *   stopAdvertising()             — stops advertising and shuts down the GATT server
 */
class DropAdvertiserService : Service() {

    companion object {
        const val NOTIFICATION_CHANNEL_ID = "drop_advertiser"
        const val NOTIFICATION_ID = 9001

        // GATT UUIDs
        private val GATT_SERVICE_UUID: UUID = UUID.fromString("12345678-1234-1234-1234-123456789abc")
        private val GATT_CHARACTERISTIC_UUID: UUID = UUID.fromString("abcdefab-cdef-abcd-efab-cdefabcdefab")

        // Intent actions
        const val ACTION_START = "com.zendfi.app.DROP_START"
        const val ACTION_STOP = "com.zendfi.app.DROP_STOP"

        // Set to true once startForeground() succeeds; false when service stops.
        // Used by MainActivity.isServiceRunning MethodChannel query.
        @Volatile var isRunning = false
    }

    private var bluetoothLeAdvertiser: BluetoothLeAdvertiser? = null
    private var bluetoothGattServer: BluetoothGattServer? = null
    private var gattCharacteristic: BluetoothGattCharacteristic? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var isAdvertising = false
    private var _lastGattValue: ByteArray? = null

    private fun svcLog(msg: String) {
        android.util.Log.d("DropAdvertiserSvc", msg)
        try {
            val f = java.io.File(filesDir, "drop_crash.log")
            val ts = java.text.SimpleDateFormat("HH:mm:ss.SSS", java.util.Locale.US).format(java.util.Date())
            f.appendText("[$ts][SVC] $msg\n")
        } catch (_: Exception) {}
    }

    // -------------------------------------------------------------------------
    // Service lifecycle
    // -------------------------------------------------------------------------

    override fun onCreate() {
        super.onCreate()
        svcLog("onCreate API=${Build.VERSION.SDK_INT}")
        createNotificationChannel()
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        svcLog("onStartCommand action=${intent?.action} API=${Build.VERSION.SDK_INT}")

        val promoted = tryStartForeground()
        if (!promoted) {
            svcLog("startForeground FAILED — stopping self to prevent crash loop")
            isRunning = false
            stopSelf()
            return START_NOT_STICKY
        }
        svcLog("startForeground OK")
        isRunning = true

        when (intent?.action) {
            ACTION_START -> {
                val extras = intent.extras
                if (extras != null) {
                    val payload = mutableMapOf<String, Any>()
                    for (key in extras.keySet()) {
                        extras.get(key)?.let { payload[key] = it }
                    }
                    if (payload.containsKey("nonce") && payload.containsKey("timestamp") && payload.containsKey("signature")) {
                        startAdvertising(payload)
                    }
                }
            }
            ACTION_STOP -> {
                stopAdvertising()
                stopSelf()
            }
            // No action — OS restarted via START_STICKY (shouldn't happen since we return
            // START_NOT_STICKY, but guard anyway).
        }

        // Use START_NOT_STICKY so if the OS kills this service, it doesn't auto-restart
        // into a crash loop. Flutter will restart it via MethodChannel when needed.
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        svcLog("onDestroy")
        isRunning = false
        stopBleAdvertising()
        stopGattServer()
        releaseWakeLock()
        super.onDestroy()
    }

    // -------------------------------------------------------------------------
    // Public API — called from MethodChannel handler in MainActivity
    // -------------------------------------------------------------------------

    /**
     * Starts BLE advertising with the given beacon payload map.
     *
     * Expected map keys (all strings):
     *   "nonce"     — UUID hex string, e.g. "550e8400-e29b-41d4-a716-446655440000"
     *   "timestamp" — Unix seconds as a numeric value (Long or Int)
     *   "signature" — HMAC-SHA256 hex string (at least 24 hex chars = 12 bytes)
     *
     * The full payload map is JSON-serialised and stored as the GATT characteristic value.
     */
    fun startAdvertising(payload: Map<String, Any>) {
        // Always tear down existing BLE + GATT state before restarting.
        // If only stopBleAdvertising() was called (old behaviour), a stale
        // GATT server would remain open, causing the second connection attempt
        // to fail silently — "drop works once then stops".
        stopBleAdvertising()
        stopGattServer()

        // Validate required fields exist before committing to a restart.
        if (!payload.containsKey("nonce") || !payload.containsKey("timestamp") || !payload.containsKey("signature")) return

        val jsonBytes = JSONObject(payload as Map<*, *>).toString().toByteArray(Charsets.UTF_8)

        startGattServer(jsonBytes)
        startBleAdvertising()
    }

    /** Stops BLE advertising and tears down the GATT server. */
    fun stopAdvertising() {
        stopBleAdvertising()
        stopGattServer()
    }

    // -------------------------------------------------------------------------
    // BLE advertising
    // -------------------------------------------------------------------------

    private fun startBleAdvertising() {
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val bluetoothAdapter = bluetoothManager?.adapter

        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled) return

        bluetoothLeAdvertiser = bluetoothAdapter.bluetoothLeAdvertiser ?: return

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(true) // connectable so GATT reads work
            .setTimeout(0)        // advertise indefinitely
            .build()

        // Primary advert: ONLY the Zend Drop service UUID.
        // A 128-bit service UUID takes 18 bytes (header + UUID), leaving only
        // 13 bytes in the 31-byte PDU — not enough for manufacturer data too.
        // The scanner identifies Zend beacons by service UUID alone; the full
        // payload is read via GATT after connection.
        val data = AdvertiseData.Builder()
            .addServiceUuid(android.os.ParcelUuid(GATT_SERVICE_UUID))
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .build()

        advertiseCallback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                isAdvertising = true
            }

            override fun onStartFailure(errorCode: Int) {
                isAdvertising = false
                val reason = when (errorCode) {
                    ADVERTISE_FAILED_DATA_TOO_LARGE -> "data too large"
                    ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "too many advertisers"
                    ADVERTISE_FAILED_ALREADY_STARTED -> "already started"
                    ADVERTISE_FAILED_INTERNAL_ERROR -> "internal error"
                    else -> "error $errorCode"
                }
                updateNotification("Drop paused — BLE advertising failed ($reason). Tap to retry.")
            }
        }

        bluetoothLeAdvertiser?.startAdvertising(settings, data, advertiseCallback)
    }

    private fun stopBleAdvertising() {
        advertiseCallback?.let { cb ->
            bluetoothLeAdvertiser?.stopAdvertising(cb)
        }
        advertiseCallback = null
        bluetoothLeAdvertiser = null
        isAdvertising = false
    }

    // -------------------------------------------------------------------------
    // GATT server
    // -------------------------------------------------------------------------

    private fun startGattServer(characteristicValue: ByteArray) {
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            ?: return

        // Store the value so we can refresh it on reconnect.
        _lastGattValue = characteristicValue

        val gattService = BluetoothGattService(
            GATT_SERVICE_UUID,
            BluetoothGattService.SERVICE_TYPE_PRIMARY
        )

        gattCharacteristic = BluetoothGattCharacteristic(
            GATT_CHARACTERISTIC_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ
        ).also { it.value = characteristicValue }

        gattService.addCharacteristic(gattCharacteristic)

        bluetoothGattServer = bluetoothManager.openGattServer(
            this,
            object : BluetoothGattServerCallback() {
                override fun onConnectionStateChange(
                    device: android.bluetooth.BluetoothDevice?,
                    status: Int,
                    newState: Int
                ) {
                    // BluetoothProfile.STATE_DISCONNECTED = 0
                    if (newState == 0) {
                        android.util.Log.d("DropAdvertiser", "GATT client disconnected: ${device?.address}")
                        // No action needed — we stay advertising and keep the GATT server open.
                        // The next sender can connect immediately without a restart.
                    }
                }

                override fun onCharacteristicReadRequest(
                    device: android.bluetooth.BluetoothDevice?,
                    requestId: Int,
                    offset: Int,
                    characteristic: BluetoothGattCharacteristic?
                ) {
                    if (characteristic?.uuid == GATT_CHARACTERISTIC_UUID) {
                        val value = gattCharacteristic?.value ?: byteArrayOf()
                        val response = if (offset < value.size) value.copyOfRange(offset, value.size)
                                       else byteArrayOf()
                        bluetoothGattServer?.sendResponse(
                            device,
                            requestId,
                            BluetoothGatt.GATT_SUCCESS,
                            offset,
                            response
                        )
                    } else {
                        bluetoothGattServer?.sendResponse(
                            device,
                            requestId,
                            BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED,
                            offset,
                            null
                        )
                    }
                }
            }
        )
        bluetoothGattServer?.addService(gattService)
    }

    private fun stopGattServer() {
        bluetoothGattServer?.close()
        bluetoothGattServer = null
        gattCharacteristic = null
    }

    // -------------------------------------------------------------------------
    // Foreground notification
    // -------------------------------------------------------------------------

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Zend Drop",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shown while Zend Drop is advertising your presence to nearby senders."
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String = "Drop is active — you're discoverable."): Notification {
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Zend Drop")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setSilent(true)
            .build()
    }

    /**
     * Attempts to promote this service to a foreground service.
     *
     * On Android 15 (API 35), [startForeground] with [ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE]
     * can throw:
     *   - [android.app.ForegroundServiceStartNotAllowedException] — app is in a state where
     *     foreground services are not permitted (battery saver, OEM restriction)
     *   - [SecurityException] — BLUETOOTH_ADVERTISE permission not granted at call time
     *
     * Both are caught here. Returns true if the service was successfully promoted,
     * false if it should abort via stopSelf() to avoid a crash-restart loop.
     */
    private fun tryStartForeground(): Boolean {
        val notification = buildNotification()
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            true
        } catch (e: Exception) {
            svcLog("startForeground THREW ${e.javaClass.name}: ${e.message}")
            android.util.Log.e("DropAdvertiser",
                "startForeground FAILED: ${e.javaClass.simpleName}: ${e.message}")
            false
        }
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager?.notify(NOTIFICATION_ID, buildNotification(text))
    }

    // -------------------------------------------------------------------------
    // WakeLock
    // -------------------------------------------------------------------------

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "ZendDrop::AdvertiserWakeLock"
        ).also { it.acquire() }
    }

    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
        wakeLock = null
    }

    // -------------------------------------------------------------------------
    // Utility — intentionally empty; hexToBytes removed (buildAdvertisementPacket deleted)
    // -------------------------------------------------------------------------
}
