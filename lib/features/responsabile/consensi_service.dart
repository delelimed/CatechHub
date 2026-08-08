// ══════════════════════════════════════════════════════════════════════════════
// consensi_service.dart — CatechHub (ciclo di vita dei consensi GDPR)
//
// Modulo "GDPR & Privacy": gestisce la scheda di iscrizione unificata firmata
// (che incorpora il consenso al trattamento dei dati del minore) e il
// contributo volontario di ciascuna famiglia.
//
// REGOLE:
//   - La "firma" della scheda unificata equivale al consenso al trattamento
//     dei dati del minore, quindi abilita [Student.consensoPrivacyFirmato].
//   - La scadenza del trattamento viene autoccalcolata come
//     dataFirma + ParishConfig.durataValiditaConsensoMesi.
//   - Ogni concessione/revoca produce una voce immutabile nel Registro
//     Trattamenti ([AuditActionType.grantConsent] / revokeConsent).
//   - La revoca non elimina la scheda (i dati restano per motivi contabili
//     e documentali) ma marca l'area privacy come non più firmata.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';

import '../../shared/models/audit_action.dart';
import '../../shared/models/audit_log.dart';
import '../../shared/models/parish_config.dart';
import '../../shared/models/student_model.dart';
import '../students/students_repository.dart';
import 'audit_log_repository.dart';
import 'parish_config_repository.dart';

/// Stato del consenso per un ragazzo, derivato dai campi GDPR dello [Student].
enum StatoConsenso {
  /// Scheda firmata e trattamento valido (entro scadenza).
  valido,

  /// Scheda firmata ma scaduta: il trattamento andrebbe rinnovato.
  scaduto,

  /// Nessuna scheda firmata: il minoren è presente in anagrafica.
  nonFirmato,
}

/// Espone lo stato GDPR di un singolo studente in forma leggibile.
class ConsensoInfo {
  final Student student;
  final StatoConsenso stato;
  final DateTime? firma;
  final DateTime? scadenza;

  const ConsensoInfo({
    required this.student,
    required this.stato,
    this.firma,
    this.scadenza,
  });

  bool get eValido => stato == StatoConsenso.valido;
  bool get eScaduto => stato == StatoConsenso.scaduto;
  bool get eFirmato => student.consensoPrivacyFirmato;
}

/// Funzioni e helper per la gestione consensi + contributo volontario.
class ConsensiService {
  ConsensiService._();

  /// Calcola lo stato del consenso del [student] alla data [now].
  static StatoConsenso stato(Student student, {DateTime? now}) {
    final oggi = (now ?? DateTime.now()).toLocal();
    if (!student.consensoPrivacyFirmato || student.dataFirmaConsenso == null) {
      return StatoConsenso.nonFirmato;
    }
    final firma = student.dataFirmaConsenso!;
    final scadenza = student.dataScadenzaTrattamento ??
        DateTime(firma.year, firma.month + 12, firma.day, 23, 59, 59);
    return scadenza.isBefore(oggi) ? StatoConsenso.scaduto : StatoConsenso.valido;
  }

  /// Costruisce la [ConsensoInfo] per un ragazzo in un solo passaggio.
  static ConsensoInfo info(Student s, {DateTime? now}) {
    final st = stato(s, now: now);
    final firma = s.dataFirmaConsenso;
    DateTime? scadenza = s.dataScadenzaTrattamento;
    if (firma != null && scadenza == null) {
      scadenza = DateTime(
          firma.year, firma.month + 12, firma.day, 23, 59, 59);
    }
    return ConsensoInfo(
      student: s,
      stato: st,
      firma: firma,
      scadenza: scadenza,
    );
  }

  /// Registra la scheda di iscrizione unificata firmata per [student].
  ///
  /// [durataMesi] (default: dalla Config parrocchiale) definisce la validità
  /// del trattamento, con scadenza calcolata automaticamente.
  static Future<void> registraScheda(
    Student student, {
    DateTime? dataFirma,
    int? durataMesi,
  }) async {
    final firma = (dataFirma ?? DateTime.now()).toLocal();
    final mesi = durataMesi ?? durataMesiDaConfig();
    final scadenza =
        DateTime(firma.year, firma.month + mesi, firma.day, 23, 59, 59);
    await StudentsRepository().updateStudent(
      student.id,
      student.copyWith(
        consensoPrivacyFirmato: true,
        dataFirmaConsenso: firma,
        dataScadenzaTrattamento: scadenza,
      ),
    );
    await _log(AuditActionType.grantConsent, student.id);
  }

  /// Revoca il consenso (scheda ritirata). Mantiene l'anagrafica.
  static Future<void> revoca(Student student) async {
    await StudentsRepository().updateStudent(
      student.id,
      student.copyWith(
        consensoPrivacyFirmato: false,
        dataFirmaConsenso: null,
        dataScadenzaTrattamento: null,
      ),
    );
    await _log(AuditActionType.revokeConsent, student.id);
  }

  /// Aggiorna il contributo volontario della famiglia.
  static Future<void> aggiornaContributo(
    Student student, {
    required bool versato,
    required double euros,
    String anno = '',
  }) async {
    await StudentsRepository().updateStudent(
      student.id,
      student.copyWith(
        contributoVersato: versato,
        contributoEuros: versato ? euros : 0,
        annoContributo: anno,
      ),
    );
  }

  /// Mesi di validità del consenso dalla configurazione parrocchiale.
  static int durataMesiDaConfig() {
    try {
      return ParishConfigRepository().getConfig().durataValiditaConsensoMesi;
    } catch (_) {
      return ParishConfig.defaultDurataConsensoMesi;
    }
  }

  static Future<void> _log(AuditActionType action, String id) async {
    try {
      await AuditLogRepository().record(
        actionType: action,
        affectedEntityId: id,
        affectedEntityType: AuditLog.entityRagazzo,
      );
    } catch (e) {
      debugPrint('[ConsensiService] AuditLog non registrato ($action): $e');
    }
  }
}