import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Gestore del database locale Hive con cifratura AES.
///
/// RUOLO NEL PROGETTO:
/// LocalDatabase è il cuore della persistenza offline di CateREG. Gestisce
/// 13 Box Hive cifrati, ognuno dedicato a un dominio dati specifico
/// (studenti, presenze, allegati, note, ecc.). L'architettura è pensata per
/// funzionare COMPLETAMENTE OFFLINE: non c'è dipendenza da un backend remoto.
/// I dati risiedono solo sul dispositivo dell'utente.
///
/// ARCHITETTURA DI RESILIENZA:
/// Ogni singolo Box viene aperto in un blocco try-catch atomico indipendente.
/// Se un Box è corrotto (file .hive danneggiato, TypeAdapter disallineato,
/// o lock residuo da crash precedente), SOLO quel Box viene eliminato dal
/// disco e ricreato vuoto. Gli altri Box restano intatti.
///
/// Questo impedisce che un singolo Box corrotto uccida l'intera applicazione,
/// problema critico per un'app usata da catechisti non tecnici su dispositivi
/// con spazio limitato e aggiornamenti irregolari.
///
/// STRUTTURA BOX:
/// ┌──────────────────────────┬──────────┬─────────────┐
/// │ Box                      │ Tipo     │ Critico     │
/// ├──────────────────────────┼──────────┼─────────────┤
/// │ registroBox (auth)       │ semplice │ SÌ          │
/// │ classes_box              │ Map      │ No          │
/// │ students_box             │ Map      │ No          │
/// │ planning_box             │ Map      │ No          │
/// │ attendance_box           │ Map      │ No          │
/// │ documents_box            │ Map      │ No          │
/// │ document_deliveries_box  │ Map      │ No          │
/// │ attachments_box          │ Map      │ No          │
/// │ contact_notes_box        │ Map      │ No          │
/// │ catechesi_box            │ Map      │ No          │
/// │ meeting_catechesi_box    │ semplice │ No          │
/// │ student_daily_notes_box  │ Map      │ No          │
/// │ trusted_devices_box      │ Map      │ No          │
/// └──────────────────────────┴──────────┴─────────────┘
///
/// Solo `registroBox` è critico: contiene la sessione autenticata (PIN,
/// preferenze, stato login). Se fallisce, l'app mostra una schermata di
/// errore fatale. Tutti gli altri Box sono recuperabili con perdita dati
/// limitata al singolo dominio.
class LocalDatabase {
// ─────────────────────────────────────────────────────────────────────────
// NOMI BOX HIVE
// Ogni costante identifica un Box Hive su disco. I nomi sono versionati
// implicitamente: se si cambia struttura dati, si apre un NUOVO Box con
// nome diverso (es. students_box_v2) e si migrano i dati. Questo evita
// conflitti di TypeAdapter tra versioni dell'app.
// ─────────────────────────────────────────────────────────────────────────
  static const authBox = 'registroBox';
  static const classesBox = 'classes_box';
  static const studentsBox = 'students_box';
  static const planningBox = 'planning_box';
  static const attendanceBox = 'attendance_box';
  static const documentsBox = 'documents_box';
  static const documentDeliveriesBox = 'document_deliveries_box';
  static const attachmentsBox = 'attachments_box';
  static const contactNotesBox = 'contact_notes_box';
  static const catechesiBox = 'catechesi_box';
  static const meetingCatechesiBox = 'meeting_catechesi_box';
  static const studentDailyNotesBox = 'student_daily_notes_box';
  static const trustedDevicesBox = 'trusted_devices_box';

  static late final HiveAesCipher _cipher;
  static bool _initialized = false;

  /// Flag per indicare che Hive.initFlutter() e' gia' stata chiamata
  /// dal metodo main(). Quando true, LocalDatabase.init() salta la
  /// chiamata a Hive.initFlutter() per evitare doppia inizializzazione.
  static bool _hiveAlreadyInitialized = false;

  /// Inizializza Hive e apre tutti i Box con cifratura AES.
  ///
  /// ACCETTA OPZIONALMENTE un [cipher] pre-configurato (es. da SecurityManager).
  /// Se non fornito, mantiene il comportamento legacy di generazione chiave
  /// locale via FlutterSecureStorage (per compatibilità/test).
  ///
  /// STRATEGIA DI RECOVERY:
  /// 1. Hive.initFlutter() viene chiamata SOLO se non e' gia' stata
  ///    invocata dal metodo main() (controlla _hiveAlreadyInitialized).
  /// 2. Se [cipher] non è fornito, recupera/genera chiave da SecureStorage.
  /// 3. Ciascuno dei 13 Box viene aperto individualmente in un try-catch.
  /// 4. Se un Box fallisce (corrotto/bloccato):
  ///    a. Il Box viene chiuso se aperto parzialmente.
  ///    b. Il Box viene eliminato da disco con Hive.deleteBoxFromDisk().
  ///    c. Il Box viene riaperto vuoto.
  /// 5. Se anche il retry individuale fallisce, l'errore viene loggato
  ///    ma l'app continua a funzionare con gli altri Box operativi.
  /// 6. L'unico Box NON opzionale e' 'authBox' (registroBox): se fallisce
  ///    dopo tutti i tentativi, l'eccezione viene propagata al chiamante
  ///    (main.dart) che mostrera' la schermata di errore fatale.
  static Future<void> init({HiveAesCipher? cipher}) async {
    if (_initialized) return;

    // ───────────────────────────────────────────────────────────────────────
    // STEP 1: Inizializzazione del motore Hive (solo se non gia' fatto).
    //
    // Hive.initFlutter() configura il percorso di archiviazione di default
    // e registra i TypeAdapter built-in. Deve essere chiamata PRIMA di
    // qualsiasi openBox.
    //
    // Se Hive.initFlutter() e' gia' stata chiamata dal metodo main()
    // (con il suo try-catch e recovery), la saltiamo qui per evitare
    // una doppia inizializzazione che potrebbe causare errori.
    // ───────────────────────────────────────────────────────────────────────
    if (!_hiveAlreadyInitialized) {
      await Hive.initFlutter();
    }

    // ───────────────────────────────────────────────────────────────────────
    // STEP 2: Configurazione cipher AES.
    // Se [cipher] è fornito (es. da SecurityManager hardware-backed), lo usa.
    // Altrimenti, fallback legacy: recupera/genera chiave da SecureStorage.
    // ───────────────────────────────────────────────────────────────────────
    if (cipher != null) {
      _cipher = cipher;
    } else {
      // LEGACY PATH: mantenuto per compatibilità e testing
      const secureStorage = FlutterSecureStorage();
      const encryptionKeyName = 'secure_database_key';

      var encryptionKeyString = await secureStorage.read(key: encryptionKeyName);
      if (encryptionKeyString == null) {
        final key = Hive.generateSecureKey();
        encryptionKeyString = base64UrlEncode(key);
        await secureStorage.write(key: encryptionKeyName, value: encryptionKeyString);
      }
      _cipher = HiveAesCipher(base64Url.decode(encryptionKeyString));
    }

    // ───────────────────────────────────────────────────────────────────────
    // STEP 3: Apertura ATOMICA INDIVIDUALE di ciascun Box.
    //
    // PROBLEMA RISOLTO: il precedente Future.wait([13 box]) faceva fallire
    // TUTTI i box se UNO solo era corrotto. Ora ogni box e' indipendente.
    //
    // PROCEDURA PER OGNI BOX:
    ///   1. Tentativo di apertura con cifratura.
    ///   2. Se fallisce → chiusura tentativi parziali → eliminazione con
    ///      Hive.deleteBoxFromDisk() → riapertura vuota.
    ///   3. Se fallisce ancora → log dell'errore e continuazione.
    ///   4. Solo authBox (registroBox) propaghera' l'eccezione fatale.
    // ───────────────────────────────────────────────────────────────────────
    final boxDefinitions = <_BoxDefinition>[
      _BoxDefinition(name: authBox, isMap: false, isCritical: true),
      _BoxDefinition(name: classesBox, isMap: true, isCritical: false),
      _BoxDefinition(name: studentsBox, isMap: true, isCritical: false),
      _BoxDefinition(name: planningBox, isMap: true, isCritical: false),
      _BoxDefinition(name: attendanceBox, isMap: true, isCritical: false),
      _BoxDefinition(name: documentsBox, isMap: true, isCritical: false),
      _BoxDefinition(name: documentDeliveriesBox, isMap: true, isCritical: false),
      _BoxDefinition(name: attachmentsBox, isMap: true, isCritical: false),
      _BoxDefinition(name: contactNotesBox, isMap: true, isCritical: false),
      _BoxDefinition(name: catechesiBox, isMap: true, isCritical: false),
      _BoxDefinition(name: meetingCatechesiBox, isMap: false, isCritical: false),
      _BoxDefinition(name: studentDailyNotesBox, isMap: true, isCritical: false),
      _BoxDefinition(name: trustedDevicesBox, isMap: true, isCritical: false),
    ];

    for (final definition in boxDefinitions) {
      await _openBoxWithRecovery(definition);
    }

    // ───────────────────────────────────────────────────────────────────────
    // STEP 4: Pulizia dati legacy.
    // Rimuove il flag 'isLoggedIn' dalla sessione persistita.
    // La sessione non viene piu' memorizzata su disco per sicurezza.
    // ───────────────────────────────────────────────────────────────────────
    try {
      await Hive.box(authBox).delete('isLoggedIn');
    } catch (e) {
      // Non fatale: il flag legacy potrebbe non esistere.
      debugPrint('[LocalDatabase] Cleanup legacy isLoggedIn fallito (non fatale): $e');
    }

    _initialized = true;
  }

  /// Marca Hive.initFlutter() come gia' completata.
  ///
  /// Da chiamare da main() dopo aver invocato Hive.initFlutter() con
  /// il suo try-catch e recovery, in modo che LocalDatabase.init() salti
  /// la doppia inizializzazione.
  static void markHiveInitialized() {
    _hiveAlreadyInitialized = true;
  }

  /// Apre un singolo Box Hive con meccanismo di auto-recovery.
  ///
  /// Se l'apertura fallisce (file corrotto, lock residuo, TypeAdapter
  /// disallineato), elimina il Box dal disco con Hive.deleteBoxFromDisk()
  /// e ritenta l'apertura una sola volta.
  ///
  /// Se il Box e' [isCritical] (cioe' authBox/registroBox) e anche il
  /// retry fallisce, l'eccezione viene propagata per far terminare
  /// l'app con una schermata di errore leggibile.
  static Future<void> _openBoxWithRecovery(_BoxDefinition definition) async {
    try {
      await _openSingleBox(definition);
    } catch (e) {
      // ─────────────────────────────────────────────────────────────────────
      // PRIMO TENTATIVO FALLITO per il Box: definition.name
      // Causa probabile: file .hive corrotto, lock residuo, o TypeAdapter
      // disallineato rispetto alla struttura dati attuale.
      // ─────────────────────────────────────────────────────────────────────
      debugPrint('[LocalDatabase] Box "${definition.name}" apertura fallita: $e');
      debugPrint('[LocalDatabase] Tentativo di recovery per "${definition.name}"...');

      try {
        // 1. Chiudi eventuali riferimenti parziali a questo Box per
        //    rilasciare i lock del filesystem.
        if (Hive.isBoxOpen(definition.name)) {
          await Hive.box(definition.name).close();
        }
      } catch (_) {
        // Chiusura best-effort: se il box non era aperto, e' un no-op.
      }

      try {
        // 2. Elimina il Box dal disco usando l'API ufficiale Hive.
        //    Hive.deleteBoxFromDisk() rimuove sia il file .hive (dati)
        //    che il file .lock (lock), garantendo un cleanup completo.
        //    Questa e' la modalita' consigliata rispetto all'eliminazione
        //    manuale dei file, perche' gestisce correttamente i edge case
        //    come i lock temporanei e i file .tmp.
        await Hive.deleteBoxFromDisk(definition.name);
        debugPrint('[LocalDatabase] Box "${definition.name}" eliminato da disco con deleteBoxFromDisk');
      } catch (deleteError) {
        // Se deleteBoxFromDisk fallisce, logghiamo ma continuiamo.
        // Il retry potrebbe comunque riuscire se il problema era solo
        // un lock transitorio.
        debugPrint('[LocalDatabase] Eliminazione Box "${definition.name}" fallita: $deleteError');
      }

      try {
        // 3. Riapri il Box vuoto (i dati precedenti sono persi ma l'app
        //    non crasha e puo' continuare a funzionare).
        await _openSingleBox(definition);
        debugPrint('[LocalDatabase] Recovery Box "${definition.name}" completato. '
            'Dati precedenti persi, Box ricreato vuoto.');
      } catch (retryError) {
        // ───────────────────────────────────────────────────────────────────
        // ANCHE IL RETRY E' FALLITO per il Box: definition.name
        // Se il Box e' critico (authBox), propaghiamo l'errore.
        // Altrimenti logghiamo e continuiamo con gli altri Box.
        // ───────────────────────────────────────────────────────────────────
        debugPrint('[LocalDatabase] Retry per "${definition.name}" fallito: $retryError');
        if (definition.isCritical) {
          rethrow;
        }
        // Box non critico: l'app puo' funzionare senza di esso.
        // I dati di questo Box saranno vuoti fino al prossimo avvio.
      }
    }
  }

  /// Apre un singolo Box Hive in base alla definizione fornita.
  /// Non effettua retry: gestisce solo l'apertura diretta.
  static Future<void> _openSingleBox(_BoxDefinition definition) async {
    if (definition.isMap) {
      await Hive.openBox<Map>(definition.name, encryptionCipher: _cipher);
    } else {
      await Hive.openBox(definition.name, encryptionCipher: _cipher);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACCESSORI AI BOX (ritornano istanze già aperte)
  // ─────────────────────────────────────────────────────────────────────────
  static Box auth() => Hive.box(authBox);
  static Box<Map> classes() => Hive.box<Map>(classesBox);
  static Box<Map> students() => Hive.box<Map>(studentsBox);
  static Box<Map> planning() => Hive.box<Map>(planningBox);
  static Box<Map> attendance() => Hive.box<Map>(attendanceBox);
  static Box<Map> documents() => Hive.box<Map>(documentsBox);
  static Box<Map> documentDeliveries() => Hive.box<Map>(documentDeliveriesBox);
  static Box<Map> attachments() => Hive.box<Map>(attachmentsBox);
  static Box<Map> contactNotes() => Hive.box<Map>(contactNotesBox);
  static Box<Map> catechesi() => Hive.box<Map>(catechesiBox);
  static Box meetingCatechesi() => Hive.box(meetingCatechesiBox);
  static Box<Map> studentDailyNotes() => Hive.box<Map>(studentDailyNotesBox);
  static Box<Map> trustedDevices() => Hive.box<Map>(trustedDevicesBox);

  // ─────────────────────────────────────────────────────────────────────────
  // UTILITÀ DI CIFRATURA BYTES
  // ─────────────────────────────────────────────────────────────────────────

  /// Cifra un array di byte usando la chiave AES di Hive.
  static Uint8List encryptBytes(Uint8List plain) {
    final out = Uint8List(_cipher.maxEncryptedSize(plain));
    final len = _cipher.encrypt(plain, 0, plain.length, out, 0);
    return Uint8List.sublistView(out, 0, len);
  }

  /// Decifra un array di byte usando la chiave AES di Hive.
  static Uint8List decryptBytes(Uint8List encrypted) {
    final out = Uint8List(encrypted.length);
    final len = _cipher.decrypt(encrypted, 0, encrypted.length, out, 0);
    return Uint8List.sublistView(out, 0, len);
  }

  /// Genera un ID univoco basato sul timestamp microsecondi.
  static String newId([String prefix = 'local']) {
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UTILITÀ DI LETTURA E OBSERVATION
  // ─────────────────────────────────────────────────────────────────────────

  /// Stream reattivo che emette la lista ogni volta che un Box cambia.
  /// Ottimizzato con throttling di 500ms per evitare ricalcoli eccessivi.
  static Stream<List<T>> watchList<T>(
    Box<Map> box,
    T Function(String id, Map<String, dynamic> data) mapper,
  ) async* {
    yield _boxValues(box, mapper);
    var lastUpdate = DateTime.now();
    await for (final _ in box.watch()) {
      if (DateTime.now().difference(lastUpdate) > const Duration(milliseconds: 500)) {
        yield _boxValues(box, mapper);
        lastUpdate = DateTime.now();
      }
    }
  }

  /// Lettura singola della lista attuale dal Box.
  static List<T> values<T>(
    Box<Map> box,
    T Function(String id, Map<String, dynamic> data) mapper,
  ) {
    return _boxValues(box, mapper);
  }

  static List<T> _boxValues<T>(
    Box<Map> box,
    T Function(String id, Map<String, dynamic> data) mapper,
  ) {
    return box.keys.map((key) {
      final id = key.toString();
      final raw = box.get(key);
      return mapper(id, toStringDynamicMap(raw));
    }).toList();
  }

  static Map<String, dynamic> toStringDynamicMap(Object? value) {
    if (value == null) return {};
    return Map<String, dynamic>.from(value as Map);
  }
}

/// Definizione di un Box Hive con le sue proprietà.
/// Utilizzata dal sistema di apertura atomica con recovery.
class _BoxDefinition {
  final String name;
  final bool isMap;
  final bool isCritical;

  const _BoxDefinition({
    required this.name,
    required this.isMap,
    required this.isCritical,
  });
}
