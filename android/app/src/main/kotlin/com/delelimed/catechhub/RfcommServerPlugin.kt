package com.delelimed.catechhub

import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

/**
 * Plugin nativo Android per la comunicazione Bluetooth Classico RFCOMM.
 *
 * Gestisce TUTTE le operazioni Bluetooth a livello nativo:
 * - Discovery dispositivi (via BroadcastReceiver nativo)
 * - Server Socket (AcceptThread con timeout generoso)
 * - Client Socket (ConnectThread con discovery + cancelDiscovery)
 * - Handshake con validazione sessionNonce
 * - Framing newline-terminated per scambio dati
 *
 * Il layer Flutter si limita a:
 * - Parsing JSON del QR code
 * - Gestione ciclo di vita
 * - Scambio dati finali (CRDT, ECDH)
 *
 * MethodChannel: "ch.catechhub.app/bluetooth_pairing"
 * EventChannel:  "ch.catechhub.app/bluetooth_pairing/events"
 */
class RfcommServerPlugin(
    private val context: Context,
    private val activityProvider: () -> Activity?
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val METHOD_CHANNEL = "ch.catechhub.app/bluetooth_pairing"
        private const val EVENT_CHANNEL = "ch.catechhub.app/bluetooth_pairing/events"

        /** UUID univoco del servizio CatechHub per discovery e connessione RFCOMM. */
        private val APP_UUID: UUID = UUID.fromString("4a8f1234-c21a-4b9d-bc32-123456789abc")

        /** Nome del servizio RFCOMM (appare nel discovery SDP). */
        private const val SERVICE_NAME = "CatechHubSync"

        /** Timeout server accept: 60 secondi (generoso per dispositivi lenti). */
        private const val SERVER_ACCEPT_TIMEOUT_SEC = 60L

        /** Timeout client connect: 30 secondi. */
        private const val CLIENT_CONNECT_TIMEOUT_SEC = 30L

        /** Timeout handshake: 10 secondi dopo la connessione. */
        private const val HANDSHAKE_TIMEOUT_SEC = 10L

        /** Timeout discovery: 30 secondi. */
        private const val DISCOVERY_TIMEOUT_SEC = 30L

        /** Prefisso nome dispositivo CatechHub. */
        private const val DEVICE_NAME_PREFIX = "CatechHub_"
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private val executor = Executors.newSingleThreadExecutor()

    // ──────────────────────────────────────────────
    //  STATO SERVER SYNC PERSISTENTE
    // ──────────────────────────────────────────────

    @Volatile private var syncServerSocket: BluetoothServerSocket? = null
    @Volatile private var syncServerThread: Thread? = null
    @Volatile private var isSyncServerRunning = false

    // ──────────────────────────────────────────────
    //  STATO SERVER PAIRING
    // ──────────────────────────────────────────────

    @Volatile private var pairingServerSocket: BluetoothServerSocket? = null
    @Volatile private var pairingServerThread: Thread? = null
    @Volatile private var isPairingServerRunning = false
    private val pairingServerExpectedNonce = AtomicReference<String?>(null)

    // ──────────────────────────────────────────────
    //  STATO DISCOVERY
    // ──────────────────────────────────────────────

    @Volatile private var isDiscoveryRunning = false
    private var discoveryReceiver: BroadcastReceiver? = null

    // ──────────────────────────────────────────────
    //  REGISTRAZIONE
    // ──────────────────────────────────────────────

    fun register(flutterEngine: FlutterEngine) {
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        )
        methodChannel?.setMethodCallHandler(this)

        eventChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL
        )
        eventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    fun unregister() {
        stopAllOperations()
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        eventSink = null
    }

    // ──────────────────────────────────────────────
    //  DISPATCH CHIAMATE
    // ──────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Generali
            "getBluetoothEnabled" -> getBluetoothEnabled(result)
            "getLocalBluetoothAddress" -> getLocalBluetoothAddress(result)
            "requestDiscoverability" -> requestDiscoverability(call, result)
            "requestBluetoothEnable" -> requestBluetoothEnable(result)

            // Discovery
            "startDiscovery" -> startDiscovery(call, result)
            "stopDiscovery" -> stopDiscovery(result)
            "getBondedDevices" -> getBondedDevices(result)

            // Nome Bluetooth
            "setLocalBluetoothName" -> setLocalBluetoothName(call, result)

            // Pairing Server
            "startPairingServer" -> startPairingServer(call, result)
            "stopPairingServer" -> stopPairingServer(result)

            // Pairing Client
            "connectPairingClient" -> connectPairingClient(call, result)

            // Sync Server
            "startSyncServer" -> startSyncServer(result)
            "stopSyncServer" -> stopSyncServer(result)
            "sendSyncData" -> sendSyncData(call, result)

            else -> result.notImplemented()
        }
    }

    // ──────────────────────────────────────────────
    //  GENERALI
    // ──────────────────────────────────────────────

    private fun getBluetoothEnabled(result: MethodChannel.Result) {
        try {
            val adapter = BluetoothAdapter.getDefaultAdapter()
            sendSuccess(result, adapter?.isEnabled == true)
        } catch (e: SecurityException) {
            sendError(result, "SECURITY_ERROR", "Permesso Bluetooth negato: ${e.message}")
        } catch (e: Exception) {
            sendError(result, "HARDWARE_FAILURE", "Errore verifica Bluetooth: ${e.message}")
        }
    }

    private fun getLocalBluetoothAddress(result: MethodChannel.Result) {
        try {
            val adapter = BluetoothAdapter.getDefaultAdapter()
            if (adapter == null) {
                sendError(result, "NO_BLUETOOTH", "Adattatore Bluetooth non disponibile")
                return
            }
            val address = adapter.address
            if (address.isNullOrEmpty() || address == "02:00:00:00:00:00") {
                sendError(result, "ADDRESS_UNAVAILABLE", "Indirizzo Bluetooth locale non disponibile")
                return
            }
            sendSuccess(result, address)
        } catch (e: SecurityException) {
            sendError(result, "SECURITY_ERROR", "Permesso Bluetooth negato: ${e.message}")
        } catch (e: Exception) {
            sendError(result, "HARDWARE_FAILURE", "Errore generico: ${e.message}")
        }
    }

    @SuppressLint("MissingPermission")
    private fun requestDiscoverability(call: MethodCall, result: MethodChannel.Result) {
        val timeout = call.argument<Int>("timeout") ?: 120

        try {
            val adapter = BluetoothAdapter.getDefaultAdapter()
            if (adapter == null) {
                sendError(result, "NO_BLUETOOTH", "Adattatore Bluetooth non disponibile")
                return
            }
            if (!adapter.isEnabled) {
                sendError(result, "BT_DISABLED", "Bluetooth disattivato")
                return
            }

            if (Build.VERSION.SDK_INT >= 31) {
                val hasPermission = context.checkSelfPermission(
                    android.Manifest.permission.BLUETOOTH_ADVERTISE
                ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                if (!hasPermission) {
                    sendError(result, "PERMISSION_DENIED", "Permesso BLUETOOTH_ADVERTISE negato")
                    return
                }
            }

            val discoverableIntent = Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).apply {
                putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, timeout)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            val appContext = context
            val resultSent = AtomicBoolean(false)

            val receiver = object : BroadcastReceiver() {
                override fun onReceive(ctx: Context, intent: Intent) {
                    if (intent.action == BluetoothAdapter.ACTION_SCAN_MODE_CHANGED) {
                        val mode = intent.getIntExtra(BluetoothAdapter.EXTRA_SCAN_MODE, BluetoothAdapter.SCAN_MODE_NONE)
                        if (mode == BluetoothAdapter.SCAN_MODE_CONNECTABLE_DISCOVERABLE) {
                            try { appContext.unregisterReceiver(this) } catch (_: Exception) {}
                            if (resultSent.compareAndSet(false, true)) {
                                sendSuccess(result, true)
                            }
                        }
                    }
                }
            }

            val filter = IntentFilter(BluetoothAdapter.ACTION_SCAN_MODE_CHANGED)
            appContext.registerReceiver(receiver, filter)

            activityProvider()?.startActivity(discoverableIntent)
                ?: context.startActivity(discoverableIntent)

            Executors.newSingleThreadExecutor().execute {
                try {
                    Thread.sleep(5000)
                    try { appContext.unregisterReceiver(receiver) } catch (_: Exception) {}
                    if (resultSent.compareAndSet(false, true)) {
                        sendSuccess(result, true)
                    }
                } catch (_: InterruptedException) {}
            }
        } catch (e: SecurityException) {
            sendError(result, "SECURITY_ERROR", "Permesso Bluetooth negato: ${e.message}")
        } catch (e: Exception) {
            sendError(result, "HARDWARE_FAILURE", "Errore discoverability: ${e.message}")
        }
    }

    @SuppressLint("MissingPermission")
    private fun requestBluetoothEnable(result: MethodChannel.Result) {
        try {
            val adapter = BluetoothAdapter.getDefaultAdapter()
            if (adapter == null) {
                sendError(result, "NO_BLUETOOTH", "Adattatore Bluetooth non disponibile")
                return
            }
            if (adapter.isEnabled) {
                sendSuccess(result, true)
                return
            }

            val enableIntent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
            enableIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activityProvider()?.startActivity(enableIntent)
                ?: context.startActivity(enableIntent)

            // Lo stato reale verrà verificato dopo che l'utente
            // risponde al dialog. Restituiamo true, il chiamante
            // può ripetere la verifica con getBluetoothEnabled.
            sendSuccess(result, true)
        } catch (e: SecurityException) {
            sendError(result, "SECURITY_ERROR", "Permesso Bluetooth negato: ${e.message}")
        } catch (e: Exception) {
            sendError(result, "HARDWARE_FAILURE", "Errore richiesta enable Bluetooth: ${e.message}")
        }
    }

    @SuppressLint("MissingPermission")
    private fun setLocalBluetoothName(call: MethodCall, result: MethodChannel.Result) {
        val name = call.argument<String>("name") ?: ""
        if (name.isBlank()) {
            sendError(result, "BAD_ARGUMENT", "Nome Bluetooth vuoto")
            return
        }
        try {
            val adapter = BluetoothAdapter.getDefaultAdapter()
            if (adapter == null) {
                sendError(result, "NO_BLUETOOTH", "Adattatore Bluetooth non disponibile")
                return
            }
            // Il nome Bluetooth è limitato a 248 byte (UTF-8)
            val truncated = if (name.toByteArray(Charsets.UTF_8).size > 248) {
                name.take(80)
            } else name
            adapter.name = truncated
            sendSuccess(result, true)
        } catch (e: SecurityException) {
            sendError(result, "SECURITY_ERROR", "Permesso Bluetooth negato: ${e.message}")
        } catch (e: Exception) {
            sendError(result, "HARDWARE_FAILURE", "Errore impostazione nome: ${e.message}")
        }
    }

    // ──────────────────────────────────────────────
    //  DISCOVERY NATIVA
    // ──────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun startDiscovery(call: MethodCall, result: MethodChannel.Result) {
        val rawFilter = call.argument<String>("deviceNameFilter") ?: ""
        val deviceNameFilter = if (rawFilter.isBlank()) null else rawFilter

        if (isDiscoveryRunning) {
            sendError(result, "DISCOVERY_ALREADY_RUNNING", "Discovery gia in corso")
            return
        }

        try {
            val adapter = BluetoothAdapter.getDefaultAdapter()
            if (adapter == null) {
                sendError(result, "NO_BLUETOOTH", "Adattatore Bluetooth non disponibile")
                return
            }
            if (!adapter.isEnabled) {
                sendError(result, "BT_DISABLED", "Bluetooth disattivato")
                return
            }

            if (Build.VERSION.SDK_INT >= 31) {
                val hasScan = context.checkSelfPermission(
                    android.Manifest.permission.BLUETOOTH_SCAN
                ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                if (!hasScan) {
                    sendError(result, "PERMISSION_DENIED", "Permesso BLUETOOTH_SCAN negato")
                    return
                }
            }

            Log.d("BLUETOOTH_CLIENT_DEBUG", "Client avvia startDiscovery()...")
            isDiscoveryRunning = true
            sendSuccess(result, "DISCOVERY_STARTED")

            val foundDevices = mutableSetOf<String>()

            discoveryReceiver = object : BroadcastReceiver() {
                override fun onReceive(ctx: Context, intent: Intent) {
                    when (intent.action) {
                        BluetoothDevice.ACTION_FOUND -> {
                            val device: BluetoothDevice? = if (Build.VERSION.SDK_INT >= 33) {
                                if (context.checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) ==
                                    android.content.pm.PackageManager.PERMISSION_GRANTED) {
                                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                                } else null
                            } else if (Build.VERSION.SDK_INT >= 31) {
                                if (context.checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) ==
                                    android.content.pm.PackageManager.PERMISSION_GRANTED) {
                                    @Suppress("DEPRECATION")
                                    intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                                } else null
                            } else {
                                @Suppress("DEPRECATION")
                                intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                            }

                            if (device != null && !foundDevices.contains(device.address)) {
                                foundDevices.add(device.address)

                                val deviceName = try {
                                    if (Build.VERSION.SDK_INT >= 31) {
                                        if (context.checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) ==
                                            android.content.pm.PackageManager.PERMISSION_GRANTED) {
                                            device.name ?: ""
                                        } else ""
                                    } else {
                                        @Suppress("DEPRECATION")
                                        device.name ?: ""
                                    }
                                } catch (_: SecurityException) { "" }

                                val deviceAddress = device.address
                                Log.d("BLUETOOTH_CLIENT_DEBUG", "Trovato dispositivo hardware -> Nome: $deviceName | MAC: $deviceAddress")

                                // Se deviceNameFilter è null, mostriamo TUTTI i dispositivi (usato in fase di pairing).
                                // Se non è null, filtriamo per nome (usato per sync background).
                                val matchesFilter = deviceNameFilter == null ||
                                    deviceName.contains(deviceNameFilter, ignoreCase = true)

                                if (matchesFilter) {
                                    Log.d("BLUETOOTH_CLIENT_DEBUG", "MATCH TROVATO! Chiamo cancelDiscovery()...")
                                    val deviceInfo = mapOf(
                                        "name" to deviceName,
                                        "address" to deviceAddress,
                                        "isBonded" to (try {
                                            device.bondState == BluetoothDevice.BOND_BONDED
                                        } catch (_: SecurityException) { false })
                                    )
                                    sendEvent("onDeviceFound", deviceInfo)
                                }
                            }
                        }
                        BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                            isDiscoveryRunning = false
                            unregisterDiscoveryReceiver()
                            sendEvent("onDiscoveryComplete", null)
                        }
                    }
                }
            }

            val filter = IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_FOUND)
                addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            }
            context.registerReceiver(discoveryReceiver, filter)

            adapter.startDiscovery()

            // Timeout discovery
            Executors.newSingleThreadExecutor().execute {
                try {
                    Thread.sleep(DISCOVERY_TIMEOUT_SEC * 1000)
                    if (isDiscoveryRunning) {
                        try { adapter.cancelDiscovery() } catch (_: Exception) {}
                        isDiscoveryRunning = false
                        unregisterDiscoveryReceiver()
                        sendEvent("onDiscoveryComplete", null)
                    }
                } catch (_: InterruptedException) {}
            }

        } catch (e: SecurityException) {
            isDiscoveryRunning = false
            sendError(result, "SECURITY_ERROR", "Permesso Bluetooth negato: ${e.message}")
        } catch (e: Exception) {
            isDiscoveryRunning = false
            sendError(result, "HARDWARE_FAILURE", "Errore discovery: ${e.message}")
        }
    }

    private fun stopDiscovery(result: MethodChannel.Result) {
        try {
            val adapter = BluetoothAdapter.getDefaultAdapter()
            if (adapter != null) {
                try { adapter.cancelDiscovery() } catch (_: SecurityException) {}
            }
            isDiscoveryRunning = false
            unregisterDiscoveryReceiver()
            sendSuccess(result, "DISCOVERY_STOPPED")
        } catch (e: Exception) {
            sendError(result, "HARDWARE_FAILURE", "Errore stop discovery: ${e.message}")
        }
    }

    @SuppressLint("MissingPermission")
    private fun getBondedDevices(result: MethodChannel.Result) {
        try {
            val adapter = BluetoothAdapter.getDefaultAdapter()
            if (adapter == null) {
                sendSuccess(result, emptyList<Any>())
                return
            }

            val devices = if (Build.VERSION.SDK_INT >= 31) {
                if (context.checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    adapter.bondedDevices?.map { device ->
                        mapOf(
                            "name" to (device.name ?: ""),
                            "address" to device.address,
                            "isBonded" to true
                        )
                    } ?: emptyList()
                } else emptyList()
            } else {
                @Suppress("DEPRECATION")
                adapter.bondedDevices?.map { device ->
                    mapOf(
                        "name" to (device.name ?: ""),
                        "address" to device.address,
                        "isBonded" to true
                    )
                } ?: emptyList()
            }

            sendSuccess(result, devices)
        } catch (e: SecurityException) {
            sendError(result, "SECURITY_ERROR", "Permesso Bluetooth negato: ${e.message}")
        } catch (e: Exception) {
            sendError(result, "HARDWARE_FAILURE", "Errore bonded devices: ${e.message}")
        }
    }

    private fun unregisterDiscoveryReceiver() {
        try {
            discoveryReceiver?.let { context.unregisterReceiver(it) }
        } catch (_: Exception) {}
        discoveryReceiver = null
    }

    // ──────────────────────────────────────────────
    //  SERVER PAIRING (AcceptThread)
    // ──────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun startPairingServer(call: MethodCall, result: MethodChannel.Result) {
        val expectedNonce = call.argument<String>("sessionNonce")
        pairingServerExpectedNonce.set(expectedNonce)

        if (isPairingServerRunning) {
            sendError(result, "SERVER_ALREADY_RUNNING", "Server pairing gia in esecuzione")
            return
        }

        executor.execute {
            try {
                val adapter = BluetoothAdapter.getDefaultAdapter()
                if (adapter == null) {
                    sendError(result, "NO_BLUETOOTH", "Adattatore Bluetooth non disponibile")
                    return@execute
                }
                if (!adapter.isEnabled) {
                    sendError(result, "BT_DISABLED", "Bluetooth disattivato")
                    return@execute
                }

                Log.d("BLUETOOTH_SERVER_DEBUG", "Server avviato, apro BluetoothServerSocket con UUID: $APP_UUID")
                val serverSocket = adapter.listenUsingRfcommWithServiceRecord(SERVICE_NAME, APP_UUID)
                isPairingServerRunning = true
                pairingServerSocket = serverSocket

                sendEvent("onPairingServerStatus", "LISTENING")
                sendSuccess(result, "PAIRING_SERVER_STARTED")

                // Accept in thread separato (non blocca l'executor)
                thread(name = "pairing-server-accept") {
                    var clientSocket: BluetoothSocket? = null
                    try {
                        Log.d("BLUETOOTH_SERVER_DEBUG", "Server in attesa bloccante (.accept())")
                        clientSocket = serverSocket.accept()
                        Log.d("BLUETOOTH_SERVER_DEBUG", "Server ha ACCETTATO la connessione da: ${clientSocket?.remoteDevice?.name ?: "sconosciuto"}")
                    } catch (e: IOException) {
                        Log.e("BLUETOOTH_ERRORE", "Errore accept: ", e)
                        return@thread
                    }

                    if (clientSocket == null || !clientSocket.isConnected) {
                        sendEvent("onPairingServerStatus", "TIMEOUT")
                        cleanupSockets(serverSocket, null)
                        isPairingServerRunning = false
                        return@thread
                    }

                    sendEvent("onPairingServerStatus", "CONNECTED")

                    // Handshake nello stesso thread
                    try {
                        val input = clientSocket!!.inputStream
                        val output = clientSocket!!.outputStream

                        val receivedPayload = readNewlineTerminatedPayload(input)
                        if (receivedPayload == null) {
                            failHandshake(serverSocket, clientSocket, "NO_PAYLOAD")
                            return@thread
                        }

                        val parts = receivedPayload.split("|")
                        if (parts.size < 3 || parts[0] != "HANDSHAKE") {
                            failHandshake(serverSocket, clientSocket, "INVALID_FORMAT")
                            return@thread
                        }

                        val clientDeviceId = parts[1]
                        val clientNonce = if (parts.size >= 3) parts[2] else ""

                        val expected = pairingServerExpectedNonce.get()
                        if (expected != null && expected != clientNonce) {
                            failHandshake(serverSocket, clientSocket, "NONCE_MISMATCH")
                            return@thread
                        }

                        val serverDeviceId = getLocalDeviceId()
                        writeNewlineTerminatedPayload(output, "ACK|$serverDeviceId|$clientNonce")

                        sendEvent("onPairingServerStatus", "HANDSHAKE_SUCCESS")
                        methodChannel?.invokeMethod("onPairingHandshakeComplete", mapOf(
                            "success" to true,
                            "peerDeviceId" to clientDeviceId
                        ))
                    } catch (e: IOException) {
                        failHandshake(serverSocket, clientSocket, "IO_ERROR:${e.message}")
                        return@thread
                    }

                    cleanupSockets(serverSocket, clientSocket)
                    isPairingServerRunning = false
                }

            } catch (e: SecurityException) {
                Log.e("BLUETOOTH_ERRORE", "Errore nativo: ", e)
                sendError(result, "SECURITY_ERROR", "Permesso Bluetooth negato: ${e.message}")
                isPairingServerRunning = false
            } catch (e: IOException) {
                Log.e("BLUETOOTH_ERRORE", "Errore nativo: ", e)
                sendError(result, "HARDWARE_FAILURE", "Errore I/O server: ${e.message}")
                isPairingServerRunning = false
            } catch (e: Exception) {
                Log.e("BLUETOOTH_ERRORE", "Errore nativo: ", e)
                sendError(result, "HARDWARE_FAILURE", "Errore generico: ${e.message}")
                isPairingServerRunning = false
            }
        }
    }

    private fun failHandshake(
        serverSocket: BluetoothServerSocket?,
        clientSocket: BluetoothSocket?,
        reason: String
    ) {
        sendEvent("onPairingServerStatus", "HANDSHAKE_FAILED")
        methodChannel?.invokeMethod("onPairingHandshakeComplete", mapOf(
            "success" to false,
            "error" to reason
        ))
        cleanupSockets(serverSocket, clientSocket)
        isPairingServerRunning = false
    }

    private fun stopPairingServer(result: MethodChannel.Result) {
        isPairingServerRunning = false
        pairingServerExpectedNonce.set(null)
        try { pairingServerSocket?.close() } catch (_: Exception) {}
        pairingServerSocket = null
        sendSuccess(result, "PAIRING_SERVER_STOPPED")
    }

    // ──────────────────────────────────────────────
    //  CLIENT PAIRING (ConnectThread)
    // ──────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun connectPairingClient(call: MethodCall, result: MethodChannel.Result) {
        val macAddress = call.argument<String>("macAddress")
            ?: return sendError(result, "BAD_ARGUMENT", "macAddress mancante")
        val sessionNonce = call.argument<String>("sessionNonce") ?: ""

        if (macAddress.isBlank()) {
            return sendError(result, "BAD_ARGUMENT", "macAddress vuoto")
        }

        val macRegex = Regex("^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$")
        if (!macRegex.matches(macAddress)) {
            return sendError(result, "BAD_ARGUMENT", "macAddress non valido: \"$macAddress\"")
        }

        executor.execute {
            var socket: BluetoothSocket? = null
            try {
                val adapter = BluetoothAdapter.getDefaultAdapter()
                if (adapter == null) {
                    sendError(result, "NO_BLUETOOTH", "Adattatore Bluetooth non disponibile")
                    return@execute
                }
                if (!adapter.isEnabled) {
                    sendError(result, "BT_DISABLED", "Bluetooth disattivato")
                    return@execute
                }

                // CRITICO: cancelDiscovery PRIMA di aprire il socket
                // Il discovery attivo dimezza le prestazioni BT e causa timeout
                try { adapter.cancelDiscovery() } catch (_: SecurityException) {}

                val device = adapter.getRemoteDevice(macAddress)
                    ?: return@execute sendError(result, "DEVICE_NOT_FOUND", "Dispositivo $macAddress non trovato")

                socket = device.createRfcommSocketToServiceRecord(APP_UUID)

                sendEvent("onPairingClientStatus", "CONNECTING")

                // Connect con timeout
                Log.d("BLUETOOTH_CLIENT_DEBUG", "Tentativo di .connect() sul socket nativo...")
                val connectThread = thread(name = "pairing-client-connect") {
                    try { socket?.connect() } catch (e: IOException) { Log.e("BLUETOOTH_ERRORE", "Errore nativo: ", e) }
                }

                connectThread.join(CLIENT_CONNECT_TIMEOUT_SEC * 1000)

                if (socket == null || !socket.isConnected) {
                    sendEvent("onPairingClientStatus", "TIMEOUT")
                    try { socket?.close() } catch (_: Exception) {}
                    sendError(result, "TIMEOUT",
                        "Connessione a $macAddress fallita entro ${CLIENT_CONNECT_TIMEOUT_SEC}s")
                    return@execute
                }

                sendEvent("onPairingClientStatus", "CONNECTED")

                // Handshake con timeout
                val handshakeResult = AtomicReference<String?>(null)
                val handshakeThread = thread(name = "pairing-client-handshake") {
                    try {
                        val input = socket!!.inputStream
                        val output = socket!!.outputStream

                        val clientDeviceId = getLocalDeviceId()
                        writeNewlineTerminatedPayload(output, "HANDSHAKE|$clientDeviceId|$sessionNonce")

                        val response = readNewlineTerminatedPayload(input)
                        if (response == null) {
                            handshakeResult.set("NO_RESPONSE")
                            return@thread
                        }

                        // Formato: ACK|{serverDeviceId}|{nonce}
                        val parts = response.split("|")
                        if (parts.size >= 2 && parts[0] == "ACK") {
                            handshakeResult.set("SUCCESS|${parts[1]}")
                        } else {
                            handshakeResult.set("REJECTED:$response")
                        }
                    } catch (e: IOException) {
                        Log.e("BLUETOOTH_ERRORE", "Errore nativo handshake client: ", e)
                        handshakeResult.set("IO_ERROR:${e.message}")
                    }
                }

                handshakeThread.join(HANDSHAKE_TIMEOUT_SEC * 1000)

                val hResult = handshakeResult.get()
                try { socket?.close() } catch (_: Exception) {}

                if (hResult != null && hResult.startsWith("SUCCESS|")) {
                    val serverDeviceId = hResult.substringAfter("SUCCESS|")
                    sendEvent("onPairingClientStatus", "HANDSHAKE_SUCCESS")
                    sendSuccess(result, "HANDSHAKE_SUCCESS")
                    methodChannel?.invokeMethod("onPairingHandshakeComplete", mapOf(
                        "success" to true,
                        "peerDeviceId" to serverDeviceId
                    ))
                } else {
                    sendEvent("onPairingClientStatus", "HANDSHAKE_FAILED")
                    sendError(result, "INVALID_HANDSHAKE",
                        "Handshake fallito: ${hResult ?: "TIMEOUT"}")
                }

            } catch (e: SecurityException) {
                Log.e("BLUETOOTH_ERRORE", "Errore nativo client: ", e)
                sendError(result, "SECURITY_ERROR", "Permesso Bluetooth negato: ${e.message}")
                try { socket?.close() } catch (_: Exception) {}
            } catch (e: IOException) {
                Log.e("BLUETOOTH_ERRORE", "Errore nativo client: ", e)
                sendError(result, "HARDWARE_FAILURE", "Errore I/O client: ${e.message}")
                try { socket?.close() } catch (_: Exception) {}
            } catch (e: Exception) {
                Log.e("BLUETOOTH_ERRORE", "Errore nativo client: ", e)
                sendError(result, "HARDWARE_FAILURE", "Errore generico: ${e.message}")
                try { socket?.close() } catch (_: Exception) {}
            }
        }
    }

    // ──────────────────────────────────────────────
    //  SYNC SERVER PERSISTENTE
    // ──────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun startSyncServer(result: MethodChannel.Result) {
        if (isSyncServerRunning) {
            sendSuccess(result, "SYNC_SERVER_ALREADY_RUNNING")
            return
        }

        executor.execute {
            try {
                val adapter = BluetoothAdapter.getDefaultAdapter()
                if (adapter == null) {
                    sendError(result, "NO_BLUETOOTH", "Adattatore Bluetooth non disponibile")
                    return@execute
                }
                if (!adapter.isEnabled) {
                    sendError(result, "BT_DISABLED", "Bluetooth disattivato")
                    return@execute
                }

                syncServerSocket = adapter.listenUsingRfcommWithServiceRecord(SERVICE_NAME, APP_UUID)
                isSyncServerRunning = true
                sendSuccess(result, "SYNC_SERVER_STARTED")

                syncServerThread = thread(name = "rfcomm-sync-server", isDaemon = true) {
                    while (isSyncServerRunning) {
                        try {
                            val clientSocket = syncServerSocket?.accept() ?: break
                            handleSyncClient(clientSocket)
                        } catch (_: IOException) {
                            if (isSyncServerRunning) {
                                try { Thread.sleep(100) } catch (_: InterruptedException) {}
                            }
                        }
                    }
                }

            } catch (e: SecurityException) {
                sendError(result, "SECURITY_ERROR", "Permesso Bluetooth negato: ${e.message}")
            } catch (e: Exception) {
                sendError(result, "HARDWARE_FAILURE", "Errore avvio sync server: ${e.message}")
            }
        }
    }

    private fun handleSyncClient(clientSocket: BluetoothSocket) {
        thread(name = "rfcomm-sync-handler", isDaemon = true) {
            try {
                val input = clientSocket.inputStream
                val buffer = StringBuilder()

                while (clientSocket.isConnected && isSyncServerRunning) {
                    val byte = input.read()
                    if (byte == -1) break

                    if (byte == 0x0A) {
                        val payload = buffer.toString()
                        if (payload.isNotEmpty()) {
                            methodChannel?.invokeMethod("onSyncDataReceived", payload)
                        }
                        buffer.clear()
                    } else if (byte != 0x0D) {
                        buffer.append(byte.toChar())
                    }

                    if (buffer.length > 10 * 1024 * 1024) {
                        buffer.clear()
                    }
                }
            } catch (_: IOException) {
            } finally {
                try { clientSocket.close() } catch (_: Exception) {}
            }
        }
    }

    private fun stopSyncServer(result: MethodChannel.Result) {
        isSyncServerRunning = false
        try { syncServerSocket?.close() } catch (_: Exception) {}
        syncServerSocket = null
        syncServerThread = null
        sendSuccess(result, "SYNC_SERVER_STOPPED")
    }

    // ──────────────────────────────────────────────
    //  INVIO DATI SYNC
    // ──────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun sendSyncData(call: MethodCall, result: MethodChannel.Result) {
        val payload = call.argument<String>("payload")
            ?: return sendError(result, "BAD_ARGUMENT", "payload mancante")
        val macAddress = call.argument<String>("macAddress")
            ?: return sendError(result, "BAD_ARGUMENT", "macAddress mancante")

        executor.execute {
            var socket: BluetoothSocket? = null
            try {
                val adapter = BluetoothAdapter.getDefaultAdapter()
                if (adapter == null) {
                    sendError(result, "NO_BLUETOOTH", "Adattatore Bluetooth non disponibile")
                    return@execute
                }

                try { adapter.cancelDiscovery() } catch (_: SecurityException) {}

                val device = adapter.getRemoteDevice(macAddress)
                    ?: return@execute sendError(result, "DEVICE_NOT_FOUND", "Dispositivo non trovato")

                socket = device.createRfcommSocketToServiceRecord(APP_UUID)

                val connectThread = thread(name = "sync-client-connect") {
                    try { socket?.connect() } catch (_: IOException) {}
                }

                connectThread.join(CLIENT_CONNECT_TIMEOUT_SEC * 1000)

                if (socket == null || !socket.isConnected) {
                    try { socket?.close() } catch (_: Exception) {}
                    sendError(result, "TIMEOUT", "Connessione sync fallita")
                    return@execute
                }

                writeNewlineTerminatedPayload(socket.outputStream, payload)
                sendSuccess(result, "DATA_SENT")
                try { socket?.close() } catch (_: Exception) {}

            } catch (e: SecurityException) {
                sendError(result, "SECURITY_ERROR", "Permesso Bluetooth negato: ${e.message}")
                try { socket?.close() } catch (_: Exception) {}
            } catch (e: IOException) {
                sendError(result, "HARDWARE_FAILURE", "Errore I/O: ${e.message}")
                try { socket?.close() } catch (_: Exception) {}
            } catch (e: Exception) {
                sendError(result, "HARDWARE_FAILURE", "Errore generico: ${e.message}")
                try { socket?.close() } catch (_: Exception) {}
            }
        }
    }

    // ──────────────────────────────────────────────
    //  LETTURA/SCRITTURA FRAMING
    // ──────────────────────────────────────────────

    private fun readNewlineTerminatedPayload(input: InputStream): String? {
        val buffer = StringBuilder()
        val singleByte = ByteArray(1)

        try {
            while (true) {
                val bytesRead = input.read(singleByte)
                if (bytesRead == -1) {
                    return if (buffer.isNotEmpty()) buffer.toString() else null
                }

                val byte = singleByte[0].toInt()

                if (byte == 0x0A) {
                    val payload = buffer.toString()
                    if (payload.isEmpty()) continue
                    return payload
                }

                if (byte != 0x0D) {
                    buffer.append(byte.toChar())
                }

                if (buffer.length > 1024 * 1024) {
                    return null
                }
            }
        } catch (e: IOException) {
            return if (buffer.isNotEmpty()) buffer.toString() else null
        }
    }

    private fun writeNewlineTerminatedPayload(output: OutputStream, payload: String) {
        val payloadBytes = payload.toByteArray(Charsets.UTF_8)
        output.write(payloadBytes)
        output.write(0x0A)
        output.flush()
    }

    // ──────────────────────────────────────────────
    //  UTILITY
    // ──────────────────────────────────────────────

    private fun getLocalDeviceId(): String {
        return try {
            val androidId = Settings.Secure.getString(
                context.contentResolver, Settings.Secure.ANDROID_ID
            ) ?: "UNKNOWN"
            "CH_${androidId.lowercase().take(12)}"
        } catch (_: Exception) {
            "CH_UNKNOWN"
        }
    }

    private fun cleanupSockets(
        serverSocket: BluetoothServerSocket?,
        clientSocket: BluetoothSocket?
    ) {
        try { clientSocket?.close() } catch (_: Exception) {}
        try { serverSocket?.close() } catch (_: Exception) {}
    }

    private fun stopAllOperations() {
        isSyncServerRunning = false
        isPairingServerRunning = false
        isDiscoveryRunning = false

        try { syncServerSocket?.close() } catch (_: Exception) {}
        try { pairingServerSocket?.close() } catch (_: Exception) {}
        try {
            val adapter = BluetoothAdapter.getDefaultAdapter()
            adapter?.cancelDiscovery()
        } catch (_: Exception) {}

        unregisterDiscoveryReceiver()

        syncServerSocket = null
        pairingServerSocket = null
    }

    // ──────────────────────────────────────────────
    //  COMUNICAZIONE CON DART
    // ──────────────────────────────────────────────

    private fun sendEvent(eventName: String, data: Any?) {
        try {
            eventSink?.success(mapOf("event" to eventName, "data" to data))
        } catch (_: Exception) {}
    }

    private fun sendError(result: MethodChannel.Result, errorCode: String, message: String) {
        try {
            result.error(errorCode, message, null)
        } catch (_: Exception) {}
    }

    private fun sendSuccess(result: MethodChannel.Result, value: Any?) {
        try {
            result.success(value)
        } catch (_: Exception) {}
    }
}
