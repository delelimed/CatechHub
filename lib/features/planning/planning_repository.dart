import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/meeting_notification_service.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models/attachment_parent_type.dart';
import '../../shared/models/planning_meeting.dart';
import '../../shared/utils/auth_utils.dart';
import '../attachments/attachments_repository.dart';

/// Provider Riverpod singleton per [PlanningRepository].
///
/// Definito a livello di file (non più in planning_provider.dart) per
/// coerenza modulare. Fornisce l'istanza condivisa del repository
/// dei meeting a tutti i widget della sezione Programmazione.
final planningRepositoryProvider = Provider<PlanningRepository>((ref) {
  return PlanningRepository();
});

/// Repository per la gestione CRUD degli eventi di programmazione.
///
/// Opera sul box Hive `planning` e si occupa di:
/// - Lettura in stream (real-time) e lettura sincrona di tutti i meeting.
/// - Inserimento di un nuovo meeting con controllo conflitto sulla stessa data.
/// - Aggiornamento di un meeting esistente; se l'evento non è una riunione,
///   aggiorna anche la data e la classe nell'archivio presenze collegato.
/// - Eliminazione a cascata: allegati (foto/PDF), associazioni catechesi,
///   record nel box planning e nell'archivio presenze.
///
/// Impedisce la duplicazione di due giornate (o due riunioni) per la
/// stessa classe nello stesso giorno.
class PlanningRepository {
  final _box = LocalDatabase.planning();

  /// Restituisce uno stream reattivo di tutti i meeting, deserializzandoli
  /// tramite [PlanningMeeting.fromMap]. Utile per aggiornamenti in tempo reale.
  Stream<List<PlanningMeeting>> getMeetings() {
    return LocalDatabase.watchList(
      _box,
      (id, data) => PlanningMeeting.fromMap(id, data),
    );
  }

  /// Restituisce la lista completa dei meeting in modo sincrono
  /// (senza stream). Usata internamente per i controlli di conflitto.
  List<PlanningMeeting> getMeetingsSync() {
    return LocalDatabase.values(
      _box,
      (id, data) => PlanningMeeting.fromMap(id, data),
    );
  }

  /// Stream dei meeting filtrati per classe.
  Stream<List<PlanningMeeting>> getPlanningByClass(String classId) {
    return LocalDatabase.watchList(
      _box,
      (id, data) => PlanningMeeting.fromMap(id, data),
    ).map((meetings) => meetings.where((m) => m.classId == classId).toList());
  }

  /// Lista sincrona dei meeting filtrati per classe.
  List<PlanningMeeting> getPlanningByClassSync(String classId) {
    return LocalDatabase.values(
      _box,
      (id, data) => PlanningMeeting.fromMap(id, data),
    ).where((m) => m.classId == classId).toList();
  }

  /// Aggiunge un nuovo meeting dopo aver verificato che non esista già
  /// un altro evento della stessa tipologia (giornata/riunione) per la
  /// stessa classe nella stessa data.
  Future<void> addMeeting(PlanningMeeting m) async {
    if (_hasMeetingOnSameDay(m)) {
      throw Exception(_sameDayError(m.isReunion));
    }

    final id = m.id.isEmpty ? LocalDatabase.newId('meeting') : m.id;
    final catechistName = getCurrentCatechistName();
    final now = DateTime.now();
    final code = m.classUniqueCode.isNotEmpty
        ? m.classUniqueCode
        : _lookupClassUniqueCode(m.classId);
    final data = m.copyWith(classUniqueCode: code).toMap();
    data['lastModifiedBy'] = catechistName;
    data['createdAt'] = now.toIso8601String();
    data['updatedAt'] = now.toIso8601String();
    await _box.put(id, data);

    // Sincronizza con le notifiche
    final meetingWithId = m.copyWith(id: id);
    await MeetingNotificationService.addOrUpdateMeeting(meetingWithId);
  }

  /// Aggiorna un meeting esistente identificato da [id].
  ///
  /// Se il meeting è una riunione, elimina l'eventuale record presenze
  /// associato. Altrimenti, se il record presenze esiste già, ne aggiorna
  /// la data e la classe per mantenerlo allineato.
  Future<void> updateMeeting(String id, PlanningMeeting m) async {
    if (_hasMeetingOnSameDay(m, excludedId: id)) {
      throw Exception(_sameDayError(m.isReunion));
    }

    final existingData = _box.get(id);
    String? existingCreatedAt;
    String? existingUniqueCode;
    if (existingData != null) {
      final map = LocalDatabase.toStringDynamicMap(existingData);
      existingCreatedAt = map['createdAt']?.toString();
      existingUniqueCode = map['classUniqueCode'] as String?;
    }
    final code = m.classUniqueCode.isNotEmpty
        ? m.classUniqueCode
        : (existingUniqueCode?.isNotEmpty == true
              ? existingUniqueCode!
              : _lookupClassUniqueCode(m.classId));
    final data = m.copyWith(classUniqueCode: code).toMap();
    data['lastModifiedBy'] = getCurrentCatechistName();
    data['createdAt'] = existingCreatedAt ?? data['createdAt'];
    data['updatedAt'] = DateTime.now().toIso8601String();
    await _box.put(id, data);

    // Sincronizza con le notifiche
    await MeetingNotificationService.addOrUpdateMeeting(m.copyWith(id: id));

    if (m.isReunion) {
      await LocalDatabase.attendance().delete(id);
      return;
    }

    final attendanceBox = LocalDatabase.attendance();
    final attendance = attendanceBox.get(id);
    if (attendance != null) {
      final updatedAttendance = LocalDatabase.toStringDynamicMap(attendance);
      updatedAttendance['date'] = m.date.toIso8601String();
      updatedAttendance['classId'] = m.classId;
      await attendanceBox.put(id, updatedAttendance);
    }
  }

  /// Elimina definitivamente un meeting e tutti i dati correlati:
  /// allegati, associazioni catechesi, record presenze e box planning.
  Future<void> deleteMeeting(String id) async {
    await AttachmentsRepository().deleteAllForParent(
      parentId: id,
      parentType: AttachmentParentType.meeting,
    );
    await LocalDatabase.meetingCatechesi().delete(id);
    await _box.delete(id);
    await LocalDatabase.attendance().delete(id);

    // Rimuovi la notifica programmata
    await MeetingNotificationService.removeMeeting(id);
  }

  /// Cerca il codice univoco di 40 cifre della classe a partire dal [classId].
  String _lookupClassUniqueCode(String classId) {
    final classData = LocalDatabase.classes().get(classId);
    if (classData == null) return '';
    final map = LocalDatabase.toStringDynamicMap(classData);
    return map['uniqueCode'] as String? ?? '';
  }

  /// Restituisce il messaggio di errore localizzato per conflitto di data,
  /// differenziando tra giornata e riunione.
  String _sameDayError(bool isReunion) {
    return isReunion
        ? 'Esiste già una riunione per questo giorno'
        : 'Esiste già una giornata per questo giorno';
  }

  /// Verifica se esiste già un meeting della stessa tipologia ([isReunion])
  /// per la stessa classe nella stessa data calendariale di [m].
  /// Se [excludedId] è specificato, quel meeting viene ignorato (utile in
  /// fase di modifica per non rilevare il meeting stesso come conflitto).
  bool _hasMeetingOnSameDay(PlanningMeeting m, {String? excludedId}) {
    final dateKey = DateTime(m.date.year, m.date.month, m.date.day);

    return getMeetingsSync().any((meeting) {
      if (meeting.id == excludedId) return false;
      final otherDate = DateTime(
        meeting.date.year,
        meeting.date.month,
        meeting.date.day,
      );
      return meeting.classId == m.classId &&
          meeting.isReunion == m.isReunion &&
          otherDate == dateKey;
    });
  }
}
