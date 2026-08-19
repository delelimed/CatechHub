// ══════════════════════════════════════════════════════════════════════════════
// hard_delete_service.dart — CatechHub (Diritto all'Oblio: eliminazione definitiva)
//
// Modulo "GDPR & Privacy" — Diritto all'Oblio:
// Esegue la cancellazione IRRIVERSIBILE di uno studente, crea il tombstone
// locale e (se sono connessi dispositivi associati) lo propaga via P2P
// cosicché il dato non possa essere "resuscitato" da un sync successivo.
//
// REGOLE:
//   - Accesso riservato: [RolePermission.rightToOblivion] (solo Responsabile).
//   - Conferma operatore: chiamate dal UI con una conferma nativa prima.
//   - Ogni hard delete logga [AuditActionType.deleteStudentHard].
//   - I tombstone sono append-only e mai cancellati automaticamente.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/auth/auth_service.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models/audit_action.dart';
import '../../shared/models/audit_log.dart';
import '../../shared/models/student_model.dart';
import '../../shared/models/user_role.dart';
import '../../features/sync/p2p/p2p_sync_service.dart';
import '../../features/sync/p2p/p2p_security_service.dart';
import '../responsabile/audit_log_repository.dart';
import '../students/students_repository.dart';
import 'tombstone_model.dart';
import 'tombstone_repository.dart';
import 'tombstone_service.dart';

/// Servizio che incapsula l'eliminazione definitiva con propagazione P2P.
class HardDeleteService {
  /// True se l'utente corrente può eseguire il Diritto all'Oblio.
  static bool canHardDelete() =>
      RolePermissions.currentCan(RolePermission.rightToOblivion);

  /// Elimina definitivamente [student] e genera il tombstone.
  ///
  /// Deve essere chiamato SOLO dopo la conferma dell'operatore. Ritorna il
  /// tombstone creato, o null se l'operazione non è permessa.
  static Future<Tombstone?> hardDeleteStudent(Student student) async {
    if (!canHardDelete()) {
      if (kDebugMode) {
        debugPrint(
          '[HardDelete] Diritto all\'Oblio non consentito per il ruolo corrente',
        );
      }
      return null;
    }

    // 1. Storale: elimina il dato (cascade) e logga DELETE_STUDENT_HARD.
    await StudentsRepository().deleteStudent(student.id);

    // 2. Crea il tombstone locale.
    final tombstone = await _buildTombstone(
      entityType: AuditLog.entityRagazzo,
      entityId: student.id,
    );
    await TombstoneRepository().put(tombstone);

    // 3. Propaga ai dispositivi associati connessi (best-effort).
    try {
      await P2PSyncService().broadcastTombstone(tombstone);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[HardDelete] Broadcast tombstone fallito (non bloccante): $e',
        );
      }
    }

    return tombstone;
  }

  /// Applica localmente lo tombstone ricevuto da un dispositivo remoto e
  /// registra l'evento [AuditActionType.tombstoneReceived].
  ///
  /// Il tombstone viene SEMPRE registrato (append-only) per impedire la
  /// "resurrezione" del dato via sync. La cancellazione irreversibile del
  /// dato, invece, viene eseguita SOLO se l'operatore locale possiede il
  /// Diritto all'Oblio (Responsabile): una firma HMAC simmetrica (segreto
  /// ECDH condiviso) autentica il mittente come dispositivo associato, ma
  /// NON è sufficiente per autorizzare la cancellazione definitiva di un
  /// minore su un dispositivo a privilegio ridotto.
  static Future<bool> applyRemoteTombstone(Map<String, dynamic> ts) async {
    final entityId = ts['entityId'] as String?;
    final entityType = ts['entityType'] as String?;
    if (entityId == null || entityId.isEmpty) return false;

    final repo = TombstoneRepository();
    // Idempotenza: il tombstone di questa entità è già stato registrato.
    if (repo.hasTombstone(entityId)) return true;

    // 0. Conserva SEMPRE il tombstone: impedisce la resurrezione via sync.
    await repo.put(_buildRemoteTombstone(ts));

    // 1. La cancellazione irreversibile richiede il Diritto all'Oblio.
    if (!canHardDelete()) {
      if (kDebugMode) {
        debugPrint(
          '[HardDelete] Tombstone registrato ma cancellazione non '
          'eseguita: l\'operatore locale non possiede il Diritto all\'Oblio',
        );
      }
      return false;
    }

    // 2. Eliminazione dell'entità nel box di origine.
    var deleted = false;
    if (entityType == AuditLog.entityRagazzo) {
      try {
        await StudentsRepository().deleteStudent(entityId);
        deleted = true;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[HardDelete] Errore cancellazione ragazzo remoto: $e');
        }
      }
    } else {
      try {
        await LocalDatabase.students().delete(entityId);
        deleted = true;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[HardDelete] Errore cancellazione entità generica: $e');
        }
      }
    }

    if (deleted) {
      // 3. Registra l'evento nel Registro Trattamenti.
      try {
        await AuditLogRepository().record(
          actionType: AuditActionType.tombstoneReceived,
          affectedEntityId: entityId,
          affectedEntityType: entityType ?? '',
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[HardDelete] Audit tombstone ricevuto non registrato: $e',
          );
        }
      }
    }

    return deleted;
  }

  static String _operatorName() {
    try {
      final name = LocalDatabase.auth().get('local_user_name') as String?;
      if (name != null && name.isNotEmpty) return name;
    } catch (_) {}
    return 'Responsabile Catechistico';
  }

  static String _operatorId() {
    try {
      final id = LocalDatabase.auth().get('catechist_id') as String?;
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {}
    return AuthService.localUserId;
  }

  static Future<Tombstone> _buildTombstone({
    required String entityType,
    required String entityId,
  }) async {
    String signer = 'unknown';
    String signingSecret = _localHello();
    try {
      final security = P2PSecurityService();
      final identity = await security.getLocalIdentity();
      signer = identity.deviceId;
      // Firma legata alla chiave privata di identità P2P: solo questo
      // dispositivo può rigenerare la firma del tombstone locale.
      final keyPair = await security.getOrCreateIdentityKeyPair();
      final privBytes = await keyPair.extractPrivateKeyBytes();
      signingSecret = base64Encode(privBytes);
    } catch (_) {}
    final deletedAt = DateTime.now().toUtc();
    final executedBy = _operatorName();
    final executedByCatechistId = _operatorId();

    final base = {
      'entityType': entityType,
      'entityId': entityId,
      'deletedAt': deletedAt.toIso8601String(),
      'executedBy': executedBy,
      'executedByCatechistId': executedByCatechistId,
      'signerDeviceId': signer,
    };
    // Firma locale (chiave legata al dispositivo, non transata via rete).
    final signature = TombstoneService.sign(
      TombstoneService.canonical(base),
      signingSecret,
    );

    return Tombstone(
      id: LocalDatabase.newId('ts'),
      entityType: entityType,
      entityId: entityId,
      deletedAt: deletedAt,
      executedBy: executedBy,
      executedByCatechistId: executedByCatechistId,
      signature: signature,
      signerDeviceId: signer,
    );
  }

  /// Costruisce il tombstone ricevuto da remoto (id generato localmente).
  static Tombstone _buildRemoteTombstone(Map<String, dynamic> ts) {
    return Tombstone(
      id: LocalDatabase.newId('ts'),
      entityType: ts['entityType'] ?? '',
      entityId: ts['entityId'] ?? '',
      deletedAt:
          DateTime.tryParse(ts['deletedAt']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      executedBy: ts['executedBy'] ?? '',
      executedByCatechistId: ts['executedByCatechistId'] ?? '',
      signature: ts['signature'] ?? '',
      signerDeviceId: ts['signerDeviceId'] ?? '',
    );
  }

  static String _localHello() {
    try {
      return AuthService.getCatechistId();
    } catch (_) {
      return AuthService.localUserId;
    }
  }
}
