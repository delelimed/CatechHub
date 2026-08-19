// ══════════════════════════════════════════════════════════════════════════════
// sync_crdt.dart — CatechHub (CRDT / Vector Clock / LWW con timestamp firmato)
//
// Modulo di risoluzione conflitti per la sincronizzazione flessibile tra
// dispositivi associati (Master-Replica). Fornisce primitive PURAMENTE
// funzionali e testabili su VM, usate dal motore di sync (HiveSyncEngine):
//
//   1. VectorClock       — log locale-first delle presenze: rileva modifiche
//                          concorrenti tra più dispositivi della stessa classe.
//   2. AttendanceCrdt    — merge per-studente Last-Write-Wins della mappa
//                          `presence` (con meta-dati `presenceMeta`):
//                          due tablet possono inserire presenze sullo stesso
//                          incontro e i risultati convergono.
//   3. SignedLww         — Last-Write-Wins SICURO: in caso di conflitto sullo
//                          stesso campo anagrafico vince la modifica con il
//                          `timestamp` firmato più recente. La firma
//                          HMAC-SHA256 (canale P2P, shared secret) impedisce
//                          di "inventare" timestamp più recenti di quelli reali.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import '../../../core/services/crypto_utils.dart';

/// Orologio vettoriale per il merge locale-first delle presenze.
///
/// Ogni nodo (dispositivo/catechista) mantiene un contatore monotono per la
/// propria entry. Confrontando due orologi si determina se una modifica
/// "accade-prima" dell'altra (causalmente ordinata) o se sono CONCORRENTI
/// (entrambe da mantenere e mergiare).
class VectorClock {
  final Map<String, int> counters;

  const VectorClock([this.counters = const {}]);

  factory VectorClock.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const VectorClock();
    final out = <String, int>{};
    for (final entry in data.entries) {
      final v = entry.value;
      if (v is num) out[entry.key] = v.toInt();
    }
    return VectorClock(out);
  }

  VectorClock increment(String node) {
    final next = Map<String, int>.from(counters);
    next[node] = (next[node] ?? 0) + 1;
    return VectorClock(next);
  }

  /// Union delle entry con i contatori massimi (merge CRDT classico).
  static VectorClock merge(VectorClock a, VectorClock b) {
    final out = <String, int>{...a.counters};
    for (final entry in b.counters.entries) {
      final cur = out[entry.key] ?? 0;
      if (entry.value > cur) out[entry.key] = entry.value;
    }
    return VectorClock(out);
  }

  /// Ritorna `true` se [this] è causalmente prima o uguale a [other].
  bool happensBeforeOrEqual(VectorClock other) {
    for (final entry in counters.entries) {
      if (entry.value > (other.counters[entry.key] ?? 0)) return false;
    }
    return true;
  }

  /// Confronto causale:
  ///  - `-1` → this precede [other] (this è vecchio, other vince)
  ///  - `+1` → [other] precede this (this vince)
  ///  - ` 0` → identici
  ///  - ` 2` → CONCORRENTI (serve il merge CRDT)
  static int compare(VectorClock a, VectorClock b) {
    final aBeforeB = a.happensBeforeOrEqual(b);
    final bBeforeA = b.happensBeforeOrEqual(a);
    if (aBeforeB && bBeforeA) return 0;
    if (aBeforeB) return -1;
    if (bBeforeA) return 1;
    return 2;
  }

  Map<String, dynamic> toMap() => Map<String, dynamic>.from(counters);
}

/// Merge CRDT della mappa `presence` di un incontro (attendance).
///
/// Formato record (attendance_box):
///   presence:      { studentId: "Presente" | "Assente" }
///   presenceMeta:  { studentId: { "t": epochMs, "by": autore } }
///
/// La presenza di ogni studente è trattata come un elemento di una
/// LWW-Element-Map: vince la scrittura con il timestamp `t` più recente;
/// a parità di timestamp vince l'autore deterministicamente (per `by`).
class AttendanceCrdt {
  AttendanceCrdt._();

  static const _presenceKey = 'presence';
  static const _metaKey = 'presenceMeta';

  static Map<String, dynamic> presenceOf(Map<String, dynamic> data) {
    final raw = data[_presenceKey];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return const {};
  }

  static Map<String, dynamic>? metaOf(Map<String, dynamic> data) {
    final raw = data[_metaKey];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  /// Confronta due meta-entry `{t, by}`. Ritorna:
  ///  - `>0` → [a] vince
  ///  - `<0` → [b] vince
  ///  - `0`  → identiche
  static int compareEntry(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ta = (a['t'] as num?)?.toInt() ?? 0;
    final tb = (b['t'] as num?)?.toInt() ?? 0;
    if (ta != tb) return ta.compareTo(tb);
    final ba = a['by']?.toString() ?? '';
    final bb = b['by']?.toString() ?? '';
    return ba.compareTo(bb);
  }

  static Map<String, dynamic> _entryMeta(int t, String by) => {
    't': t,
    'by': by,
  };

  /// Costruisce `presenceMeta` a partire dalla `presence` quando il record
  /// ricevuto è legacy (senza meta): attribuisce ogni presenza all'autore con
  /// il timestamp del record. In questo modo anche i vecchi dati partecipano
  /// al CRDT con una granularità ragionevole.
  static Map<String, dynamic> buildMetaFallback(
    Map<String, dynamic> presence, {
    required int recordTimestampMs,
    required String author,
  }) {
    final meta = <String, dynamic>{};
    for (final sid in presence.keys) {
      meta[sid] = _entryMeta(recordTimestampMs, author);
    }
    return meta;
  }

  /// Esegue il merge convergente di due record di presenza.
  ///
  /// Ritorna la mappa `{ 'presence': {...}, 'presenceMeta': {...} }` da
  /// scrivere nel record mergiato. Gli studenti presenti solo su un lato
  /// vengono presi così come sono; quelli su entrambi vengono risolti con
  /// il confronto LWW per-entry.
  static Map<String, dynamic> mergePresence({
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
  }) {
    final localPresence = presenceOf(localData);
    final remotePresence = presenceOf(remoteData);
    final localMeta = metaOf(localData);
    final remoteMeta = metaOf(remoteData);

    final localTs =
        (DateTime.tryParse(
          localData['updatedAt']?.toString() ?? '',
        )?.toUtc().millisecondsSinceEpoch ??
        0);
    final remoteTs =
        (DateTime.tryParse(
          remoteData['updatedAt']?.toString() ?? '',
        )?.toUtc().millisecondsSinceEpoch ??
        0);

    final localAuthor = (localData['lastModifiedBy'] ?? localData['updatedAt'])
        .toString();
    final remoteAuthor =
        (remoteData['lastModifiedBy'] ?? remoteData['updatedAt']).toString();

    final resolvedMeta = <String, dynamic>{};
    final mergedPresence = <String, dynamic>{};

    final allStudents = <String>{...localPresence.keys, ...remotePresence.keys};

    for (final sid in allStudents) {
      final lv = localPresence[sid];
      final rv = remotePresence[sid];

      final lm = localMeta != null && localMeta[sid] is Map
          ? Map<String, dynamic>.from(localMeta[sid] as Map)
          : (lv != null ? _entryMeta(localTs, localAuthor) : null);
      final rm = remoteMeta != null && remoteMeta[sid] is Map
          ? Map<String, dynamic>.from(remoteMeta[sid] as Map)
          : (rv != null ? _entryMeta(remoteTs, remoteAuthor) : null);

      if (lv != null && rv != null && lm != null && rm != null) {
        final cmp = compareEntry(lm, rm);
        if (cmp >= 0) {
          mergedPresence[sid] = lv;
          resolvedMeta[sid] = lm;
        } else {
          mergedPresence[sid] = rv;
          resolvedMeta[sid] = rm;
        }
      } else if (lv != null) {
        mergedPresence[sid] = lv;
        if (lm != null) resolvedMeta[sid] = lm;
      } else if (rv != null) {
        mergedPresence[sid] = rv;
        if (rm != null) resolvedMeta[sid] = rm;
      }
    }

    return {_presenceKey: mergedPresence, _metaKey: resolvedMeta};
  }

  /// true se il record è un record di presenza (attendance).
  static bool isAttendanceRecord(String boxName) => boxName == 'attendance_box';
}

/// Timestamp firmato HMAC-SHA256 per il Last-Write-Wins sicuro.
///
/// Firma il `updatedAt` di un record con il shared secret del canale P2P
/// (lo stesso schema di TombstoneService). Chi riceve può verificare che il
/// timestamp non sia stato contraffatto: un dispositivo non può dichiarare
/// un aggiornamento "più recente" di quello che ha realmente prodotto.
class SignedLww {
  SignedLww._();

  static const _prefix = 'CatechHub_SignedTS_v1';

  /// Canonicizza il riferimento a un record per la firma.
  static String canonical({
    required String boxName,
    required String recordId,
    required String updatedAtIso,
  }) {
    return '$_prefix|$boxName|$recordId|$updatedAtIso';
  }

  /// Firma HMAC-SHA256 (base64) del timestamp del record con [secretKey].
  static String sign({
    required String boxName,
    required String recordId,
    required String updatedAtIso,
    required String secretKey,
  }) {
    final mac = hmacSha256BytesSync(
      utf8.encode(secretKey),
      utf8.encode(
        canonical(
          boxName: boxName,
          recordId: recordId,
          updatedAtIso: updatedAtIso,
        ),
      ),
    );
    return base64Encode(mac);
  }

  /// Verifica la firma di un record (confronto tempo-costante).
  /// Ritorna `false` se la firma manca, è vuota o non corrisponde.
  static bool verify({
    required String boxName,
    required String recordId,
    required String updatedAtIso,
    required String? signature,
    required String secretKey,
  }) {
    if (signature == null || signature.isEmpty || secretKey.isEmpty) {
      return false;
    }
    final expected = sign(
      boxName: boxName,
      recordId: recordId,
      updatedAtIso: updatedAtIso,
      secretKey: secretKey,
    );
    return _constantTimeEquals(expected, signature);
  }

  /// Decide quale record vince sul campo anagrafico in conflitto.
  ///
  /// Precedenza:
  ///   1. Se [secretKey] è disponibile e la firma del record più "nuovo" è
  ///      VALIDA, vince il record con il timestamp firmato più recente.
  ///      Se il timestamp più recente NON ha firma valida (contraffatto),
  ///      vince l'altro (sicurezza: rifiutiamo timestamp inventati).
  ///   2. Fallback legacy senza chiave: vince il timestamp più recente.
  ///
  /// Ritorna `true` se vince il record remoto, `false` se vince quello locale.
  static bool remoteWins({
    required String boxName,
    required String recordId,
    required String localUpdatedAtIso,
    required String? localSignature,
    required String remoteUpdatedAtIso,
    required String? remoteSignature,
    required String secretKey,
  }) {
    final localTs = DateTime.tryParse(localUpdatedAtIso);
    final remoteTs = DateTime.tryParse(remoteUpdatedAtIso);
    if (localTs == null) return true;
    if (remoteTs == null) return false;

    if (secretKey.isNotEmpty) {
      final localValid = verify(
        boxName: boxName,
        recordId: recordId,
        updatedAtIso: localUpdatedAtIso,
        signature: localSignature,
        secretKey: secretKey,
      );
      final remoteValid = verify(
        boxName: boxName,
        recordId: recordId,
        updatedAtIso: remoteUpdatedAtIso,
        signature: remoteSignature,
        secretKey: secretKey,
      );

      if (remoteTs.isAfter(localTs)) {
        // Il remoto dichiara di essere più recente: pretendiamo la firma.
        return remoteValid;
      }
      if (localTs.isAfter(remoteTs)) {
        // Il locale dichiara di essere più recente: se la sua firma non è
        // valida, lasciamo vincere il remoto (sicuro).
        return !localValid;
      }
      // Timestamp identici: vince la firma valida, poi deterministicamente.
      if (remoteValid != localValid) return remoteValid;
      return false;
    }

    // Legacy: nessuna chiave → semplice confronto timestamp.
    return remoteTs.isAfter(localTs);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
