// ══════════════════════════════════════════════════════════════════════════════
// normal_mode_sync_handler.dart — CatechHub (Modalità Normale — reingegnerizzata)
//
// REINGEGNERIZZAZIONE COMPLETA DELLA SINCRONIZZAZIONE IN MODALITÀ NORMALE
// (NON ALTERA LA MODALITÀ RESPONSABILE).
//
// REQUISITI UTENTE (tradotti in contratto tecnico):
//   1) "Mio Dispositivo"  → condividere SEMPRE anche il catechistId stabile.
//      Due dispositivi della STESSA persona devono convergere sullo stesso
//      catechistId, così da sincronizzare TUTTE le classi e permettere lavoro
//      offline indipendente + riconvergenza realtime quando vicini via Nearby.
//   2) "Altro Catechista" → associare il catechista remoto alla(e) classe(i)
//      condivisa(e) (campi catechistIds / associatedCatechistIds /
//      catechistRoles / catechistDeviceCounts) e subito avviare la
//      condivisione dei dati: entrambi i catechisti lavorano singolarmente
//      sugli STESSI dati (copia locale completa della classe condivisa) e
//      sincronizzano in tempo reale quando i dispositivi sono vicini (Nearby
//      Connections, Strategy.P2P_CLUSTER — SOLO P2P via Bluetooth/WiFi Direct,
//      MAI internet).
//   3) Cifratura "standard militare" e GDPR per dati particolari di minori:
//      - in transito: X25519 ECDH + HKDF-SHA256 + AES-256-GCM (FIPS 140-2,
//        NSA Suite B), forward secrecy con chiavi effimere per-sessione,
//        nonce 96-bit casuale, AAD di contesto (binding classe/sessione),
//        rotazione chiavi ogni 30 min, MITM detection via pairing code SAS +
//        public-key pinning;
//      - a riposo: Hive AES-256 + FieldEncryptionService per campi PII
//        sensibili (allergie, note, telefoni) con chiave per-dispositivo;
//      - minimizzazione: sync per-classe (scope), tombstones per diritto
//        all'oblio, audit log, blocco demo-PII;
//
// INVARIANTE: ogni metodo qui sotto è NOP in modalità Responsabile
// (AppModeUtils.isResponsabileMode == true). La modalità Responsabile resta
// governata da P2PSecurityService catena di fiducia / trust root.
// ══════════════════════════════════════════════════════════════════════════════

import '../../../core/auth/auth_service.dart';
import '../../../core/storage/local_database.dart';
import '../../../shared/utils/app_mode.dart';
import '../p2p/hive_sync_engine.dart';
import '../p2p/p2p_sync_service.dart';

/// Handler dedicato alla sola modalità normale (AppMode.normal / associato
/// non-responsabile). Tutta la mutazione di Hive/box è centralizzata qui così
/// da rendere auditabile il contratto dei due flussi.
class NormalModeSyncHandler {
  NormalModeSyncHandler._();

  /// True se siamo in modalità normale (non responsabile).
  static bool get isNormalContext => !AppModeUtils.isResponsabileMode;

  // ─────────────────────────────────────────────────────────────────────────
  // FLUSSO 1: "Mio Dispositivo" — condivisione catechistId
  // ─────────────────────────────────────────────────────────────────────────

  /// Condivide il catechistId locale con il peer durante il pairing
  /// "Mio Dispositivo".
  ///
  /// Chiamato DOPO che il pairing code è stato verificato e l'associazione
  /// salvata. Se il dispositivo locale è fresco (senza identità catechistica
  /// propria), adotta l'id del primario così che entrambi convergano sulla
  /// stessa identità stabile. Il catechistId è già trasportato cifrato in
  /// p2p_identity (AES-256-GCM con shared secret ECDH), mai in chiaro sul
  /// canale BLE.
  ///
  /// Ritorna true se l'adozione è avvenuta.
  static Future<bool> shareCatechistIdForMyDevice({
    required String remoteCatechistId,
    required P2PSyncRole localRole,
    required P2PSyncRole? remoteRole,
  }) async {
    if (!isNormalContext) return false;
    if (localRole != P2PSyncRole.mioDispositivo) return false;
    if (remoteRole != null && remoteRole != P2PSyncRole.mioDispositivo) {
      return false;
    }
    if (remoteCatechistId.isEmpty) return false;

    final local = AuthService.getCatechistId();
    if (local == remoteCatechistId) return false;

    // Adozione solo se il locale non ha ancora una propria identità
    // (nessuna classe associata al suo catechistId). Evita di sovrascrivere
    // un catechista che ha già classi proprie.
    if (_hasCatechistIdentity(local)) return false;

    AuthService.adoptCatechistId(remoteCatechistId);
    return true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FLUSSO 2: "Altro Catechista" — associazione alla classe + condivisione
  // ─────────────────────────────────────────────────────────────────────────

  /// Associa il catechista remoto [remoteCatechistId] alle classi condivise
  /// [sharedClassIds] (se vuoto → classi comuni / fallback locale).
  ///
  /// Effetti atomici per ogni classe toccata:
  ///   - catechistIds += remoteCatechistId
  ///   - associatedCatechistIds += remoteCatechistId
  ///   - catechistRoles[remoteCatechistId] = TITOLARE (se assente)
  ///   - catechistDeviceCounts[remoteCatechistId] = 1 (o incrementa)
  ///   - creatorCatechistId valorizzato se vuoto
  ///   - updatedAt = now (trigger per il sync watcher)
  ///
  /// Dopo questa chiamata entrambi i dispositivi possiedono la stessa classe
  /// (stesso uniqueCode, stessi member) e possono lavorare offline
  /// indipendentemente: le modifiche locali vengono accodate in Hive e
  /// riconvergenti via CRDT LWW + merge per-classe quando i dispositivi
  /// tornano vicini (Nearby discovery + _watchLocalChanges).
  static Future<int> associateOtherCatechistToSharedClasses({
    required String remoteCatechistId,
    required Set<String> sharedClassIds,
    String remoteName = '',
  }) async {
    if (!isNormalContext) return 0;
    if (remoteCatechistId.isEmpty) return 0;

    final box = LocalDatabase.classes();
    const localId = AuthService.localUserId;
    final localCatechistId = AuthService.getCatechistId();
    var touched = 0;

    // Se nessuna selezione esplicita, ricadi sulle classi comuni/locali
    // (stesso comportamento del sync scope di P2PSyncService).
    final effectiveShared = sharedClassIds.isNotEmpty
        ? sharedClassIds
        : _commonOrLocalClassIds(localCatechistId, remoteCatechistId);

    for (final key in box.keys) {
      final id = key.toString();
      if (effectiveShared.isNotEmpty && !effectiveShared.contains(id)) {
        continue;
      }
      final data = LocalDatabase.toStringDynamicMap(box.get(key));
      final ids = (data['catechistIds'] as List? ?? [])
          .map((e) => e.toString())
          .toList();
      // Tocchiamo solo classi di cui il locale fa parte (o che non hanno
      // ancora una ownership chiara — retrocompatibilità).
      final isLocalClass = _isLocalClass(data, localCatechistId);
      if (!isLocalClass && ids.contains(localId)) {
        // fallback: se localId è nel roster legacy, considerala locale
      } else if (!isLocalClass && effectiveShared.isEmpty) {
        continue;
      }

      var mutated = false;

      // — roster ufficiale —
      if (!ids.contains(remoteCatechistId)) {
        ids.add(remoteCatechistId);
        data['catechistIds'] = ids;
        mutated = true;
      }

      // — associatedCatechistIds (scoping) —
      var associated = (data['associatedCatechistIds'] as List? ?? [])
          .map((e) => e.toString())
          .toList();
      if (!associated.contains(remoteCatechistId)) {
        associated.add(remoteCatechistId);
        data['associatedCatechistIds'] = associated;
        mutated = true;
      }

      // — catechistRoles —
      final roles = data['catechistRoles'] is Map
          ? Map<String, String>.from(data['catechistRoles'] as Map)
          : <String, String>{};
      if (!roles.containsKey(remoteCatechistId)) {
        roles[remoteCatechistId] = 'TITOLARE';
        data['catechistRoles'] = roles;
        mutated = true;
      }

      // — catechistDeviceCounts —
      final counts = data['catechistDeviceCounts'] is Map
          ? (data['catechistDeviceCounts'] as Map).map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            )
          : <String, int>{};
      counts[remoteCatechistId] = (counts[remoteCatechistId] ?? 0) + 1;
      data['catechistDeviceCounts'] = counts;

      if ((data['creatorCatechistId'] as String? ?? '').isEmpty) {
        data['creatorCatechistId'] = localCatechistId;
        mutated = true;
      }

      if (mutated || counts.isNotEmpty) {
        data['updatedAt'] = DateTime.now().toUtc().toIso8601String();
        await box.put(id, data);
        touched++;
      }
    }
    return touched;
  }

  /// Verifica post-sync che il catechista remoto sia effettivamente presente
  /// nella(e) classe(i) condivisa(e). Usata come guard di integrità dopo
  /// _applyPendingRemoteProfileIfNeeded / _ensureLocalCatechistInClasses.
  static bool isCatechistInSharedClasses(
    String catechistId,
    Set<String> sharedClassIds,
  ) {
    if (catechistId.isEmpty) return false;
    final box = LocalDatabase.classes();
    for (final key in box.keys) {
      if (sharedClassIds.isNotEmpty && !sharedClassIds.contains(key.toString())) {
        continue;
      }
      final data = LocalDatabase.toStringDynamicMap(box.get(key));
      final ids = (data['catechistIds'] as List? ?? [])
          .map((e) => e.toString())
          .toList();
      if (ids.contains(catechistId)) return true;
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SYNC REAL-TIME QUANDO VICINI (Nearby) — realtime, offline-first
  // ─────────────────────────────────────────────────────────────────────────

  /// Costruisce lo scope di sync per la modalità normale.
  ///
  /// - "Mio Dispositivo" (stesso catechistId o entrambi mioDispositivo) → null
  ///   (tutte le classi, perché sono la stessa persona su più device).
  /// - "Altro Catechista" → solo le classi condivise (quelle scelte al pairing
  ///   o le classi comuni ai due catechistId). Lista vuota = nessun sync.
  ///
  /// Le PII di classi fuori scope NON sono mai costruite nell'indice né
  /// inviate (minimizzazione GDPR art.5(1)(c)).
  static Future<List<SyncClassScope>?> buildNormalSyncScope({
    required String? remoteCatechistId,
    required Set<String> sharedClassIds,
    String? localRoleName,
    String? remoteRoleName,
  }) async {
    if (!isNormalContext) return null;
    final localCatechistId = AuthService.getCatechistId();

    // Stessa persona → tutte le classi
    if (remoteCatechistId != null &&
        remoteCatechistId.isNotEmpty &&
        remoteCatechistId == localCatechistId) {
      return null;
    }
    if (localRoleName == P2PSyncRole.mioDispositivo.name &&
        remoteRoleName == P2PSyncRole.mioDispositivo.name) {
      return null;
    }

    final candidates = <String>{...sharedClassIds};
    if (candidates.isEmpty) {
      candidates.addAll(
        _commonClassIds(localCatechistId, remoteCatechistId),
      );
    }
    if (candidates.isEmpty) return const [];

    final localOwned = _getClassIdsForCatechist(localCatechistId);
    final sendable = candidates.where(localOwned.contains).toSet();
    if (sendable.isEmpty && localOwned.isNotEmpty) return const [];

    return _buildScopes(sendable);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CIFRATURA MILITARE — contratto documentato (non altera responsabile)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // Stack crittografico per la modalità normale (identico al canale P2P
  // esistente, qui solo reso esplicito e auditabile):
  //   • Scambio chiavi: X25519 ECDH (RFC 7748, 256-bit, ~128-bit security).
  //     Ogni sessione combina 4 DH (static↔static, static↔ephemeral x2,
  //     ephemeral↔ephemeral) → TripleDH + binding identità. Le chiavi
  //     effimere sono per-sessione, MAI persistite (forward secrecy).
  //   • Derivazione chiavi: HKDF-SHA256 (RFC 5869) con info
  //     "CatechHub_P2P_Session_v3:<ids>:<windowId>" e nonce di handshake
  //     concordato (combinazione ordinata dei due nonce casuali).
  //   • Cifratura: AES-256-GCM (FIPS 140-2, 256-bit key, nonce 96-bit casuale,
  //     tag 128-bit) con AAD di contesto "CatechHub_Context_P2P_v1" (binding
  //     anti-substitution). Fallback ChaCha20-Poly1305 ove disponibile.
  //   • Rotazione: finestra 30 min (sessionWindowIndex), mantenendo finestra
  //     corrente + precedente per messaggi in transito.
  //   • Autenticazione: public-key pinning + SAS 6-cifre (pairing code)
  //     derivato da shared secret + nonce + chiavi effimere ordinate; MitM
  //     su efimera → SAS diverge.
  //   • A riposo: Hive AES-256 (chiave in Keystore/Keychain) + cifratura di
  //     campo per PII (allergie, note, telefoni) con chiave per-dispositivo.
  //
  // GDPR (dati particolari minori, art.9 + art.32):
  //   - cifratura in transito e a riposo, pseudonimizzazione (catechistId
  //     invece di nome), minimizzazione (solo classi condivise), limitazione
  //     conservazione (associazioni 30gg), diritto oblio via tombstones,
  //     privacy by design (campi sensibili cifrati prima di lasciare il device).
  // ─────────────────────────────────────────────────────────────────────────

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers (mirror ridotto di P2PSyncService, volutamente duplicato per
  // non toccare il servizio responsabile).
  // ─────────────────────────────────────────────────────────────────────────

  static bool _hasCatechistIdentity(String catechistId) {
    if (catechistId.isEmpty) return false;
    try {
      final box = LocalDatabase.classes();
      final isLocalCat = catechistId == AuthService.getCatechistId();
      for (final key in box.keys) {
        final data = LocalDatabase.toStringDynamicMap(box.get(key));
        final creator = data['creatorCatechistId']?.toString() ?? '';
        final associated = (data['associatedCatechistIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        final catechistIds = (data['catechistIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        final creatorId = data['creatorId']?.toString() ?? '';
        bool owned = catechistId == creator || associated.contains(catechistId);
        if (!owned) {
          if (catechistIds.contains(catechistId)) {
            owned = true;
          }
          if (!owned && isLocalCat) {
            if (catechistIds.contains(AuthService.localUserId) ||
                creatorId == AuthService.localUserId) {
              owned = true;
            }
          }
        }
        if (owned) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  static bool _isLocalClass(Map<String, dynamic> data, String localCatechistId) {
    if (localCatechistId.isEmpty) return false;
    final creator = data['creatorCatechistId']?.toString() ?? '';
    if (creator == localCatechistId) {
      return true;
    }
    final associated = (data['associatedCatechistIds'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    if (associated.contains(localCatechistId)) {
      return true;
    }
    // Legacy fallback: catechistIds con constant
    final catechistIds = (data['catechistIds'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    if (catechistIds.contains(localCatechistId)) {
      return true;
    }
    if (localCatechistId == AuthService.getCatechistId()) {
      if (catechistIds.contains(AuthService.localUserId)) {
        return true;
      }
      if ((data['creatorId']?.toString() ?? '') == AuthService.localUserId) {
        return true;
      }
    }
    return false;
  }

  static Set<String> _getClassIdsForCatechist(String? catechistId) {
    if (catechistId == null || catechistId.isEmpty) return {};
    final ids = <String>{};
    try {
      final box = LocalDatabase.classes();
      final isLocalCat = catechistId == AuthService.getCatechistId();
      for (final key in box.keys) {
        final data = LocalDatabase.toStringDynamicMap(box.get(key));
        final creator = data['creatorCatechistId']?.toString() ?? '';
        final associated = (data['associatedCatechistIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        final catechistIds = (data['catechistIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        final creatorId = data['creatorId']?.toString() ?? '';
        bool owned = catechistId == creator || associated.contains(catechistId);
        if (!owned) {
          if (catechistIds.contains(catechistId)) {
            owned = true;
          }
          if (!owned && isLocalCat) {
            if (catechistIds.contains(AuthService.localUserId) ||
                creatorId == AuthService.localUserId) {
              owned = true;
            }
          }
        }
        if (owned) ids.add(key.toString());
      }
    } catch (_) {}
    return ids;
  }

  static Set<String> _commonClassIds(String? a, String? b) {
    if (a == null || a.isEmpty || b == null || b.isEmpty) return {};
    return _getClassIdsForCatechist(a).intersection(_getClassIdsForCatechist(b));
  }

  static Set<String> _commonOrLocalClassIds(
    String localCatechistId,
    String remoteCatechistId,
  ) {
    final common = _commonClassIds(localCatechistId, remoteCatechistId);
    if (common.isNotEmpty) return common;
    return _getClassIdsForCatechist(localCatechistId);
  }

  static List<SyncClassScope> _buildScopes(Set<String> classIds) {
    final box = LocalDatabase.classes();
    final scopes = <SyncClassScope>[];
    for (final id in classIds) {
      final data = LocalDatabase.toStringDynamicMap(box.get(id));
      final code = data['uniqueCode']?.toString() ?? '';
      scopes.add(SyncClassScope(classId: id, classUniqueCode: code));
    }
    return scopes;
  }
}
