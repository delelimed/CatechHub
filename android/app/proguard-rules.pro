# =========================================================================
# ABILITAZIONE OTTIMIZZAZIONI AGGRESIVE
# =========================================================================
# Consente a R8 di fare passaggi di ottimizzazione più profondi.
-repackageclasses ''
-allowaccessmodification

# =========================================================================
# 1. FLUTTER CORE & ENGINE (Ottimizzato)
# =========================================================================
# Invece di bloccare tutto con { *; }, preserviamo solo i punti di ingresso 
# e le annotazioni usate dal motore Flutter per l'interoperabilità nativa.
-keep class io.flutter.app.** { public *; }
-keep class io.flutter.plugin.** { public *; }
-keep class io.flutter.util.** { public *; }
-keep class io.flutter.view.** { public *; }
-keep class io.flutter.embedding.** { public *; }
-keep class io.flutter.plugins.** { public *; }

# Keep per i metodi nativi (JNI) e i canali di comunicazione
-keepclasseswithmembernames class * {
    native <methods>;
}
-keepattributes Signature,*Annotation*,InnerClasses,EnclosingMethod

# =========================================================================
# 2. HIVE (Zona Franca selettiva)
# =========================================================================
# Non serve bloccare interamente i package di Hive, ma solo le classi 
# che estendono HiveObject o che usano le annotazioni per la serializzazione.
-keep class TypeAdapter { *; }
-keep class * extends io.isar.hive.HiveObject { *; }
-keepclasseswithmembers class * {
    @io.isar.hive.HiveType <fields>;
    @io.isar.hive.HiveField <fields>;
}
# Permetti a R8 di ottimizzare l'interno di Hive ma ignora i warning di build
-dontwarn io.hybridshapes.hive.**
-dontwarn io.isar.hive.**

# =========================================================================
# 3. LOCAL AUTH & BIOMETRIC (Raffinamento)
# =========================================================================
# Manteniamo solo l'interfaccia pubblica e le classi necessarie
-keep class io.flutter.plugins.localauth.** { public *; }
-keep class androidx.biometric.BiometricPrompt { public *; }
-dontwarn androidx.biometric.**

# =========================================================================
# 4. FLUTTER SECURE STORAGE & TINK (Taglio drastico della memoria)
# =========================================================================
# Tink (com.google.crypto.tink) è mastodontico. Dire `-keep class com.google.crypto.tink.** { *; }` 
# carica in RAM megabyte di crittografia inutilizzata. Lasciamo che R8 elimini il superfluo.
-keep class com.it_nomads.fluttersecurestorage.** { public *; }
-dontwarn com.it_nomads.fluttersecurestorage.**
-dontwarn com.google.crypto.tink.**

# =========================================================================
# 5. MOBILE SCANNER (ML Kit)
# =========================================================================
# ML Kit è un altro gigante. Non bloccare l'intero SDK. Manteniamo solo 
# i punti di ingresso usati dal plugin per la scansione.
-keep class com.google.mlkit.vision.barcode.** { public *; }
-keep class dev.nhancv.mlkit_camera_stream.** { public *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_vision_barcode.**

# =========================================================================
# 6. PRINTING, PDF & DEVICE INFO
# =========================================================================
# Rimuoviamo il blocco totale `{ *; }` e usiamo `public *` per consentire 
# l'offuscamento delle logiche interne non visibili dall'esterno.
-keep class net.nfet.flutter.printing.** { public *; }
-keep class dev.fluttercommunity.plus.packageinfo.** { public *; }
-keep class dev.fluttercommunity.plus.deviceinfo.** { public *; }

# =========================================================================
# 7. TUO CANALE BLUETOOTH NATIVO (ch.catechhub.app)
# =========================================================================
# Poiché usi un MethodChannel personalizzato scritto in Kotlin, dobbiamo 
# assicurarci che la classe del tuo plugin e i metodi richiamati via riflessione 
# non vengano eliminati. Manteniamo la classe e i suoi membri pubblici.
-keep class ch.catechhub.app.** {
    public *;
}

# =========================================================================
# 8. COMPONENTI DEFERITI & UTILITY
# =========================================================================
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# =========================================================================
# 9. PROTEZIONE FREERASP (TALSEC)
# =========================================================================
# Essendo un tool di sicurezza, ha regole rigide. Manteniamo solo la configurazione.
-keep class com.talsec.RasterConfig { *; }
-dontwarn com.talsec.**