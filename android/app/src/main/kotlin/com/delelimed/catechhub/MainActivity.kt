package com.delelimed.catechhub

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.view.WindowManager
import android.os.Bundle
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.File
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.MGF1ParameterSpec
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource

/**
 * Activity principale dell'applicazione CatechHub.
 *
 * CatechHub è un'applicazione Flutter pensata per i catechisti parrocchiali,
 * che gestisce un registro elettronico di catechismo contenente dati sensibili
 * di minori (anagrafica, contatti dei genitori, allergie, presenze).
 *
 * Questa Activity funge da ponte nativo Android (MethodChannel) verso il layer
 * Dart/Flutter, e si occupa di:
 *
 * 1. **Sicurezza dello schermo** (FLAG_SECURE): impedisce screenshot eregistrazioni
 *    dello schermo, prottendo i dati degli studenti da accessi non autorizzati.
 *    L'utente può attivare/disattivare questa funzione dalle impostazioni dell'app.
 *
 * 2. **Gestione chiavi crittografiche RSA** tramite Android KeyStore: genera,
 *    recupera, firma, verifica, cifra e decifra dati utilizzando coppie di chiavi
 *    RSA 2048-bit memorizzate in modo sicuro nel hardware del dispositivo.
 *    Queste chiavi sono fondamentali per lo scambio peer-to-peer via Bluetooth
 *    (RFCOMM), dove ogni catechista ha una propria coppia di chiavi per autenticare
 *    e cifrare i dati sincronizzati.
 *
 * 3. **Plugin Bluetooth RFCOMM**: registra e gestisce il plugin per la
 *    sincronizzazione Bluetooth Classic tra dispositivi catechisti, basata su
 *    CRDT (Last-Write-Wins) per la risoluzione conflitti e scambio di chiavi
 *    pubbliche tramite codici QR.
 *
 * La struttura a MethodChannel consente a Flutter di invocare funzionalità native
 * Android in modo asincrono, mantenendo la separazione tra il codice Dart
 * (logica di Business) e il codice Kotlin (operazioni crittografiche sicure).
 */
class MainActivity : FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Pulizia APK scaricati ad ogni avvio dell'app
        cleanupOldApks()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CANALI METHOD CHANNEL
    // ─────────────────────────────────────────────────────────────────────────
    // I MethodChannel fungono da ponte di comunicazione tra il codice Dart
    // (Flutter) e il codice Kotlin nativo (Android). Ogni canale ha un nome
    // univoco che identifica il dominio funzionale.
    // ─────────────────────────────────────────────────────────────────────────

    /** Canale per le operazioni di sicurezza generiche (FLAG_SECURE, versione SDK). */
    private val securityChannel = "com.delelimed.catechhub/security"

    /** Canale per le operazioni crittografiche sul KeyStore RSA (chiavi, firma, cifratura). */
    private val keystoreChannel = "com.delelimed.catechhub/keystore"

    // ─────────────────────────────────────────────────────────────────────────
    // PLUGIN RFCOMM
    // ─────────────────────────────────────────────────────────────────────────
    // Il plugin RFCOMM gestisce la comunicazione Bluetooth Classic tra i
    // dispositivi dei catechisti. Viene utilizzato per la sincronizzazione
    // peer-to-peer dei dati (anagrafica, presenze, incontri) senza bisogno
    // di un server centrale, in linea con la filosofia privacy-first dell'app.
    // ─────────────────────────────────────────────────────────────────────────

    /** Istanza del plugin RFCOMM, null se il Bluetooth non è disponibile. */
    private var rfcommServerPlugin: RfcommServerPlugin? = null

    // ─────────────────────────────────────────────────────────────────────────
    // CONFIGURAZIONE KEYSTORE RSA
    // ─────────────────────────────────────────────────────────────────────────
    // Android KeyStore è un container sicuro per le chiavi crittografiche che
    // le protegge a livello hardware, impedendo anche ad altre app (o al
    // sistema operativo) di accedere alle chiavi private in chiaro.
    // Le chiavi RSA generate qui vengono utilizzate per:
    // - Firma digitale dei dati scambiati via Bluetooth (SHA512withRSA)
    // - Cifratura/decifratura dei payload (RSA/ECB/OAEPPadding)
    // - Scambio di chiavi pubbliche tramite QR code durante l'abbinamento
    //   (pairing) tra dispositivi catechisti
    // ─────────────────────────────────────────────────────────────────────────

    /** Provider della Android KeyStore, il keystore hardware-backed del dispositivo. */
    private val KEYSTORE_PROVIDER = "AndroidKeyStore"

    /** Algoritmo asimmetrico utilizzato per la generazione delle coppie di chiavi. */
    private val KEY_ALGORITHM = "RSA"

    /** Dimensione della chiave RSA in bit. 2048-bit è lo standard consigliato. */
    private val KEY_SIZE = 2048

    /** Algoritmo per la firma digitale dei dati (hash SHA-512 + padding RSA PKCS1). */
    private val SIGNATURE_ALGORITHM = "SHA512withRSA"

    /** Trasformazione per la cifratura/decifratura RSA con padding OAEP (sicuro). */
    private val CIPHER_TRANSFORMATION = "RSA/ECB/OAEPPadding"

    /** Specifica OAEP per la cifratura RSA: usa SHA-256 come hash e MGF1 come mask generation function. */
    private val OAEP_SPEC = OAEPParameterSpec(
        "SHA-256",
        "MGF1",
        MGF1ParameterSpec.SHA256,
        PSource.PSpecified.DEFAULT
    )

    /** Scope coroutine per le operazioni I/O crittografiche, con SupervisorJob per isolare i fallimenti. */
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // ─────────────────────────────────────────────────────────────────────────
    // CONFIGURAZIONE DEL FLUTTER ENGINE
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Configura il Flutter Engine registrando i plugin nativi e i MethodChannel
     * necessari al funzionamento dell'app.
     *
     * Questo metodo viene invocato automaticamente dall'embedding v2 di Flutter
     * all'avvio dell'activity. Il ordine di inizializzazione è importante:
     * 1. Chiamata a super per la registrazione automatica dei plugin Flutter
     * 2. Registrazione del plugin RFCOMM (Bluetooth)
     * 3. Registrazione dei MethodChannel per sicurezza e crittografia
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Viene omesso l'uso esplicito di GeneratedPluginRegistrant.registerWith.
        // L'embedding v2 di Flutter esegue la registrazione automatica integrata dei plugin.
        super.configureFlutterEngine(flutterEngine)

        // Registrazione sicura del plugin Bluetooth RFCOMM.
        // Il Bluetooth potrebbe non essere disponibile su alcuni dispositivi (es. tablet WiFi-only),
        // quindi l'inizializzazione è protetta da un blocco try-catch per evitare crash.
        try {
            rfcommServerPlugin = RfcommServerPlugin(this) { this }
            rfcommServerPlugin?.register(flutterEngine)
        } catch (e: Exception) {
            android.util.Log.e(
                "MainActivity",
                "RfcommServerPlugin init fallito (Bluetooth non disponibile?): $e"
            )
            rfcommServerPlugin = null
        }

        // SECURITY CHANNEL
        // Gestisce le operazioni di sicurezza generiche dall'interfaccia Flutter.
        // Supporta due metodi:
        // - setSecureFlag: attiva/disattiva FLAG_SECURE sulla finestra dell'activity,
        //   impedendo screenshot e registrazioni dello schermo. Fondamentale per
        //   proteggere i dati sensibili degli studenti (anagrafica, allergie, contatti).
        // - getAndroidSdkVersion: restituisce la versione dell'SDK Android in uso,
        //   necessaria per adattare il comportamento dell'app alle diverse versioni del SO.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, securityChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecureFlag" -> {
                        val requested = call.argument<Boolean>("enabled") ?: false
                        runOnUiThread {
                            if (requested) {
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
                    "getAndroidSdkVersion" -> {
                        result.success(Build.VERSION.SDK_INT)
                    }
                    "openSecuritySettings" -> {
                        runOnUiThread {
                            try {
                                val intent = Intent(Settings.ACTION_SECURITY_SETTINGS)
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("SECURITY_SETTINGS_ERROR", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // KEYSTORE CHANNEL
        // Gestisce tutte le operazioni crittografiche RSA tramite Android KeyStore.
        // Tutte le operazioni vengono eseguite su una coroutine I/O dedicata per
        // non bloccare il thread principale, e i risultati vengono restituiti
        // al thread UI tramite runOnMain.
        //
        // Metodi supportati:
        // - generateKeyPair: genera una nuova coppia di chiavi RSA nel KeyStore
        // - getPublicKey: recupera la chiave pubblica associata a un alias
        // - signData: firma dati con la chiave privata (per autenticazione)
        // - verifySignature: verifica una firma con la chiave pubblica
        // - encryptWithPublicKey: cifra dati con una chiave pubblica
        // - decryptWithPrivateKey: decifra dati con la chiave privata
        // - keyExists: verifica se esiste una chiave con l'alias indicato
        // - deleteKey: elimina una chiave dal KeyStore
        // - listKeys: elenca tutti gli alias delle chiavi presenti nel KeyStore
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, keystoreChannel)
            .setMethodCallHandler { call, result ->
                ioScope.launch {
                    try {
                        when (call.method) {
                            "generateKeyPair" -> {
                                val alias = call.argument<String>("alias")
                                    ?: return@launch runOnMain { result.error("BAD_ARGUMENT", "Alias mancante", null) }
                                val publicKey = generateKeyPair(alias)
                                runOnMain { result.success(publicKey) }
                            }
                            "getPublicKey" -> {
                                val alias = call.argument<String>("alias")
                                    ?: return@launch runOnMain { result.error("BAD_ARGUMENT", "Alias mancante", null) }
                                val publicKey = getPublicKey(alias)
                                runOnMain { result.success(publicKey) }
                            }
                            "signData" -> {
                                val alias = call.argument<String>("alias")
                                    ?: return@launch runOnMain { result.error("BAD_ARGUMENT", "Alias mancante", null) }
                                val data = call.argument<String>("data")
                                    ?: return@launch runOnMain { result.error("BAD_ARGUMENT", "Data mancante", null) }
                                val signature = signData(alias, data)
                                runOnMain { result.success(signature) }
                            }
                            "verifySignature" -> {
                                val publicKey = call.argument<String>("publicKey")
                                    ?: return@launch runOnMain { result.error("BAD_ARGUMENT", "PublicKey mancante", null) }
                                val data = call.argument<String>("data")
                                    ?: return@launch runOnMain { result.error("BAD_ARGUMENT", "Data mancante", null) }
                                val signature = call.argument<String>("signature")
                                    ?: return@launch runOnMain { result.error("BAD_ARGUMENT", "Signature mancante", null) }
                                val isValid = verifySignature(publicKey, data, signature)
                                runOnMain { result.success(isValid) }
                            }
                            "encryptWithPublicKey" -> {
                                val publicKey = call.argument<String>("publicKey")
                                    ?: return@launch runOnMain { result.error("BAD_ARGUMENT", "PublicKey mancante", null) }
                                val data = call.argument<String>("data")
                                    ?: return@launch runOnMain { result.error("BAD_ARGUMENT", "Data mancante", null) }
                                val encrypted = encryptWithPublicKey(publicKey, data)
                                runOnMain { result.success(encrypted) }
                            }
                            "decryptWithPrivateKey" -> {
                                val alias = call.argument<String>("alias")
                                    ?: return@launch runOnMain { result.error("BAD_ARGUMENT", "Alias mancante", null) }
                                val encryptedData = call.argument<String>("encryptedData")
                                    ?: return@launch runOnMain { result.error("BAD_ARGUMENT", "EncryptedData mancante", null) }
                                val decrypted = decryptWithPrivateKey(alias, encryptedData)
                                runOnMain { result.success(decrypted) }
                            }
                            "keyExists" -> {
                                val alias = call.argument<String>("alias")
                                    ?: return@launch runOnMain { result.error("BAD_ARGUMENT", "Alias mancante", null) }
                                val exists = keyExists(alias)
                                runOnMain { result.success(exists) }
                            }
                            "deleteKey" -> {
                                val alias = call.argument<String>("alias")
                                    ?: return@launch runOnMain { result.error("BAD_ARGUMENT", "Alias mancante", null) }
                                deleteKey(alias)
                                runOnMain { result.success(null) }
                            }
                            "listKeys" -> {
                                val keys = listKeys()
                                runOnMain { result.success(keys) }
                            }
                            else -> runOnMain { result.notImplemented() }
                        }
                    } catch (e: Exception) {
                        runOnMain {
                            result.error("KEYSTORE_ERROR", e.localizedMessage ?: e.message, null)
                        }
                    }
}
        }
}

    /**
     * Utility per eseguire un'azione sul thread UI.
     * Utilizzato per restituire i risultati delle operazioni crittografiche
     * (eseguite su thread I/O) al MethodChannel Flutter, che richiede
     * la restituzione sul thread principale.
     */
    private fun runOnMain(action: () -> Unit) {
        runOnUiThread { action() }
    }

    /**
     * Ciclo di vita dell'activity: pulizia delle risorse alla distruzione.
     * Cancella lo scope coroutine e deregistra il plugin RFCOMM per liberare
     * la risorsa Bluetooth. La deregistrazione è protetta da try-catch perché
     * potrebbe fallire se il Bluetooth non era stato inizializzato correttamente.
     */
    override fun onDestroy() {
        ioScope.cancel()
        try {
            rfcommServerPlugin?.unregister()
        } catch (e: Exception) {
            android.util.Log.w("MainActivity", "Errore deregistrazione RFCOMM (non fatale): $e")
        }
        super.onDestroy()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // OPERAZIONI KEYSTORE RSA NATIVE
    // ─────────────────────────────────────────────────────────────────────────
    // Le seguenti funzioni implementano le operazioni crittografiche RSA
    // utilizzando Android KeyStore come backend sicuro. Le chiavi private
    // non lasciano mai il secure enclave del dispositivo.
    //
    // Flusso tipico di utilizzo nel contesto dell'app:
    // 1. All'avvio dell'app, viene generata una coppia di chiavi RSA
    // 2. La chiave pubblica viene esportata e scambiate via QR code
    //    durante l'abbinamento (pairing) tra dispositivi catechisti
    // 3. I dati sincronizzati via Bluetooth vengono firmati con la
    //    chiave privata per garantirne l'autenticità
    // 4. I dati sensibili vengono cifrati con la chiave pubblica del
    //    destinatario per garantirne la riservatezza
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Genera una nuova coppia di chiavi RSA nel Android KeyStore.
     *
     * La chiave viene generata con le seguenti caratteristiche:
     * - Algoritmo: RSA 2048-bit
     * - Purpose: firma, verifica, cifratura, decifratura
     * - Signature padding: PKCS1 (compatibile con SHA512withRSA)
     * - Encryption padding: OAEP (più sicuro di PKCS1 per la cifratura)
     * - Digest: SHA-256 e SHA-512
     *
     * La chiave privata rimane nel secure hardware del dispositivo e non
     * può essere estratta, nemmeno da altre app o dal sistema operativo.
     *
     * @param alias Identificativo univoco della coppia di chiavi nel KeyStore
     * @return Chiave pubblica encodata in Base64 (formato X.509)
     */
    private fun generateKeyPair(alias: String): String {
        val keyPairGenerator = KeyPairGenerator.getInstance(KEY_ALGORITHM, KEYSTORE_PROVIDER)
        val spec = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY or
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setKeySize(KEY_SIZE)
            .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
            .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA512)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_OAEP)
            .build()

        keyPairGenerator.initialize(spec)
        val keyPair = keyPairGenerator.generateKeyPair()
        return Base64.getEncoder().encodeToString(keyPair.public.encoded)
    }

    /**
     * Recupera la chiave pubblica associata a un alias dal KeyStore.
     *
     * Utilizzato per ottenere la chiave pubblica da scambiare con altri
     * dispositivi catechisti durante il pairing via QR code, o per verificare
     * firme digitali ricevute.
     *
     * @param alias Identificativo della coppia di chiavi
     * @return Chiave pubblica in Base64, oppure null se l'alias non esiste
     */
    private fun getPublicKey(alias: String): String? {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER)
        keyStore.load(null)
        if (!keyStore.containsAlias(alias)) return null
        val certificate = keyStore.getCertificate(alias) ?: return null
        return Base64.getEncoder().encodeToString(certificate.publicKey.encoded)
    }

    /**
     * Firma dati utilizzando la chiave privata associata a un alias.
     *
     * La firma digitale garantisce l'autenticità e l'integrità dei dati
     * scambiati via Bluetooth tra i dispositivi catechisti. Un ricevente
     * può verificare che i dati siano stati effettivamente inviati dal
     * catechista possessore della chiave privata.
     *
     * @param alias Identificativo della chiave privata da utilizzare per la firma
     * @param data Stringa UTF-8 da firmare
     * @return Firma digitale codificata in Base64
     */
    private fun signData(alias: String, data: String): String {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER)
        keyStore.load(null)
        val privateKey = keyStore.getKey(alias, null) as PrivateKey
        val signature = Signature.getInstance(SIGNATURE_ALGORITHM)
        signature.initSign(privateKey)
        signature.update(data.toByteArray(Charsets.UTF_8))
        return Base64.getEncoder().encodeToString(signature.sign())
    }

    /**
     * Verifica la validità di una firma digitale utilizzando la chiave pubblica.
     *
     * Utilizzato durante la sincronizzazione Bluetooth per validare l'origine
     * e l'integrità dei dati ricevuti da un altro dispositivo catechista.
     *
     * @param publicKeyStr Chiave pubblica del firmatario in Base64 (formato X.509)
     * @param data Dati originali che sono stati firmati
     * @param signatureStr Firma digitale da verificare in Base64
     * @return true se la firma è valida, false altrimenti
     */
    private fun verifySignature(publicKeyStr: String, data: String, signatureStr: String): Boolean {
        val publicKeyBytes = Base64.getDecoder().decode(publicKeyStr)
        val keySpec = X509EncodedKeySpec(publicKeyBytes)
        val keyFactory = java.security.KeyFactory.getInstance(KEY_ALGORITHM)
        val publicKey = keyFactory.generatePublic(keySpec)

        val signature = Signature.getInstance(SIGNATURE_ALGORITHM)
        signature.initVerify(publicKey)
        signature.update(data.toByteArray(Charsets.UTF_8))

        val signatureBytes = Base64.getDecoder().decode(signatureStr)
        return signature.verify(signatureBytes)
    }

    /**
     * Cifra dati utilizzando una chiave pubblica (RSA con padding OAEP).
     *
     * La cifratura garantisce la riservatezza dei dati: solo il possessore
     * della chiave privata corrispondente può decifrarli. Utilizzato per
     * proteggere i dati sensibili (anagrafica minori, allergie, contatti)
     * durante lo scambio via Bluetooth.
     *
     * @param publicKeyStr Chiave pubblica del destinatario in Base64
     * @param data Dati da cifrare in formato stringa UTF-8
     * @return Dati cifrati codificati in Base64
     */
    private fun encryptWithPublicKey(publicKeyStr: String, data: String): String {
        val publicKeyBytes = Base64.getDecoder().decode(publicKeyStr)
        val keySpec = X509EncodedKeySpec(publicKeyBytes)
        val keyFactory = java.security.KeyFactory.getInstance(KEY_ALGORITHM)
        val publicKey = keyFactory.generatePublic(keySpec)

        val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, publicKey, OAEP_SPEC)

        val encryptedBytes = cipher.doFinal(data.toByteArray(Charsets.UTF_8))
        return Base64.getEncoder().encodeToString(encryptedBytes)
    }

    /**
     * Decifra dati utilizzando la chiave privata associata a un alias.
     *
     * Utilizzato per decifrare i dati ricevuti da un altro catechista
     * che li ha cifrati con la nostra chiave pubblica. La chiave privata
     * rimane nel secure enclave di Android e non viene mai esportata.
     *
     * @param alias Identificativo della chiave privata da utilizzare
     * @param encryptedData Dati cifrati in Base64
     * @return Dati decifrati in formato stringa UTF-8
     */
    private fun decryptWithPrivateKey(alias: String, encryptedData: String): String {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER)
        keyStore.load(null)
        val privateKey = keyStore.getKey(alias, null) as PrivateKey
        val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, privateKey, OAEP_SPEC)

        val encryptedBytes = Base64.getDecoder().decode(encryptedData)
        val decryptedBytes = cipher.doFinal(encryptedBytes)
        return String(decryptedBytes, Charsets.UTF_8)
    }

    /**
     * Verifica l'esistenza di una chiave con l'alias indicato nel KeyStore.
     *
     * Utilizzato dall'app Flutter per determinare se è necessario generare
     * una nuova coppia di chiavi o se ne esiste già una valida.
     *
     * @param alias Identificativo della chiave da verificare
     * @return true se esiste una chiave con l'alias indicato
     */
    private fun keyExists(alias: String): Boolean {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER)
        keyStore.load(null)
        return keyStore.containsAlias(alias)
    }

    /**
     * Elimina una chiave dal KeyStore.
     *
     * Utilizzato per la gestione del ciclo di vita delle chiavi: ad esempio
     * quando un catechista vuole rigenerare le proprie chiavi o quando
     * l'app viene disinstallata/resetata.
     *
     * @param alias Identificativo della chiave da eliminare
     */
    private fun deleteKey(alias: String) {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER)
        keyStore.load(null)
        if (keyStore.containsAlias(alias)) {
            keyStore.deleteEntry(alias)
        }
    }

    /**
     * Elenca tutti gli alias delle chiavi presenti nel KeyStore.
     *
     * Utilizzato per il debug e per la gestione delle chiavi:
     * consente di verificare quali chiavi sono attualmente memorizzate
     * nel dispositivo.
     *
     * @return Lista di stringhe contenente gli alias di tutte le chiavi
     */
    private fun listKeys(): List<String> {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER)
        keyStore.load(null)
        return keyStore.aliases().toList()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // OPERAZIONI AGGIORNAMENTO APK (FILEPROVIDER)
    // ─────────────────────────────────────────────────────────────────────────
    // Installazione APK tramite FileProvider per compatibilità Android 7+ (API 24+).
    // Evita "package parsing error" usando content:// URI invece di file:// URI.
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Installa un file APK usando FileProvider per condividere il file
     * con il Package Installer di Android.
     *
     * Su Android 7+ (API 24+), i file:// URI non sono più consentiti per
     * Intent cross-app. FileProvider genera un content:// URI con permessi
     * di lettura temporanei (FLAG_GRANT_READ_URI_PERMISSION).
     *
     * @param apkPath Percorso assoluto del file APK da installare
     * @param result Result callback per Flutter
     */
    private fun installApk(apkPath: String, result: MethodChannel.Result) {
        val apkFile = File(apkPath)
        if (!apkFile.exists()) {
            runOnMain { result.error("FILE_NOT_FOUND", "APK non trovato: $apkPath", null) }
            return
        }

        try {
            val uri = FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                apkFile
            )

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            // Verifica che ci sia un activity che può gestire l'intent
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
                runOnMain { result.success(null) }
            } else {
                runOnMain { result.error("NO_HANDLER", "Nessun installer APK disponibile", null) }
            }
        } catch (e: Exception) {
            runOnMain { result.error("INSTALL_ERROR", e.localizedMessage ?: e.message, null) }
        }
    }

    /**
     * Elimina file .apk residui dalle directory dell'app.
     * Chiamato all'avvio per pulire eventuali APK scaricati ma non installati.
     */
    private fun cleanupOldApks() {
        val dirs = mutableListOf<File?>(
            externalCacheDir,
            getExternalFilesDir(null),
            filesDir,
            cacheDir
        )

        // Aggiungi directory Download e Documents se accessibili
        try {
            val downloads = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            val documents = getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS)
            if (downloads != null) dirs.add(downloads)
            if (documents != null) dirs.add(documents)
        } catch (e: Exception) {
            // Ignore
        }

        for (dir in dirs) {
            if (dir == null || !dir.exists()) continue
            try {
                for (file in dir.listFiles() ?: emptyArray()) {
                    if (file.isFile && file.extension == "apk") {
                        file.delete()
                    }
                }
            } catch (e: Exception) {
                // Ignore cleanup errors
            }
        }
    }
}
