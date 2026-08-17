import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/field_encryption_service.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models/attachment_parent_type.dart';
import '../../shared/models/audit_action.dart';
import '../../shared/models/audit_log.dart';
import '../../shared/models/student_model.dart';
import '../../shared/models/historical_record.dart';
import '../../shared/utils/auth_utils.dart';
import '../../shared/utils/name_formatting.dart';
import '../archive/historical_record_repository.dart';
import '../attachments/attachments_repository.dart';
import '../responsabile/audit_log_repository.dart';
import 'student_daily_notes_repository.dart';

final studentsRepositoryProvider =
    Provider<StudentsRepository>((ref) {
  return StudentsRepository();
});

/// Repository per le operazioni CRUD sugli studenti nel Box `students`
/// di Hive. Offre metodi asincroni (add, update, delete) e sincroni
/// (getAllStudentsSync) per l'anagrafica ragazzi.
/// La cancellazione ([deleteStudent]) esegue una cascade delete che
/// rimuove allegati ([AttachmentsRepository]), annotazioni giornaliere
/// ([StudentDailyNotesRepository]), riferimenti nelle classi, presenze
/// e consegne documenti. I dati in ingresso vengono normalizzati
/// (capitalizzazione nomi, pulizia spazi) tramite [_normalize].
class StudentsRepository {
  final _box = LocalDatabase.students();

  Future<void> addStudent(Student student) async {
    final id = student.id.isEmpty ? LocalDatabase.newId('student') : student.id;
    final catechistName = getCurrentCatechistName();
    final now = DateTime.now();
    final code = student.classUniqueCode ?? _lookupClassUniqueCode(student.classId);
    // L5 / Fase 4-12: cifratura di campo PRIMA della persistenza. In passato
    // i dati uscivano in chiaro dal repository (birthDate, telefoni, email,
    // allergie...), mentre il path P2P/import cifrava già i campi: incoerenza.
    // encryptStudentMapForStorage è idempotente (lascia invariato ciò che è
    // già cifrato) e i valori cifrati vengono decifrati in lettura da
    // [_studentFromBox].
    await _box.put(id, FieldEncryptionService.encryptStudentMapForStorage(
      _normalize(student).copyWith(
        classUniqueCode: code,
        lastModifiedBy: catechistName,
        createdAt: now,
        updatedAt: now,
      ).toMap(),
    ));
    await _log(AuditActionType.createStudent, id, AuditLog.entityRagazzo);
  }

  Stream<List<Student>> getAllStudents() {
    return LocalDatabase.watchList(
      _box,
      (id, data) => _studentFromBox(id, data),
    ).map(Student.sortedBySurname);
  }

  Stream<List<Student>> getStudents() => getAllStudents();

  /// Stream degli studenti filtrati per classe.
  Stream<List<Student>> getStudentsByClass(String classId) {
    return LocalDatabase.watchList(
      _box,
      (id, data) => _studentFromBox(id, data),
    ).map((students) => Student.sortedBySurname(
      students.where((s) => s.classId == classId),
    ));
  }

  /// Lista sincrona degli studenti filtrati per classe.
  List<Student> getStudentsByClassSync(String classId) {
    return Student.sortedBySurname(
      LocalDatabase.values(
        _box,
        (id, data) => _studentFromBox(id, data),
      ).where((s) => s.classId == classId),
    );
  }

  List<Student> getAllStudentsSync() {
    return Student.sortedBySurname(
      LocalDatabase.values(
        _box,
        (id, data) => _studentFromBox(id, data),
      ),
    );
  }

  /// Deserializza dal Box decifrando i campi sensibili cifrati a livello
  /// di campo (es. [Student.noteAllergieSalute]).
  Student _studentFromBox(String id, Map<String, dynamic> data) {
    final decrypted = FieldEncryptionService.decryptStudentMapForTransport(data);
    final student = Student.fromMap(id, decrypted);
    return student;
  }

  Future<void> updateStudent(String id, Student student) async {
    final catechistName = getCurrentCatechistName();
    final existing = _box.get(id);
    DateTime? existingCreatedAt;
    String? existingUniqueCode;
    if (existing != null) {
      final map = LocalDatabase.toStringDynamicMap(existing);
      existingCreatedAt = DateTime.tryParse(map['createdAt']?.toString() ?? '');
      existingUniqueCode = map['classUniqueCode'];
    }
    final code = student.classUniqueCode ?? existingUniqueCode ?? _lookupClassUniqueCode(student.classId);
    // L5 / Fase 4-12: cifratura di campo prima della persistenza (vedi
    // addStudent). I valori già cifrati restano invariati (idempotente).
    await _box.put(id, FieldEncryptionService.encryptStudentMapForStorage(
      _normalize(student).copyWith(
        classUniqueCode: code,
        lastModifiedBy: catechistName,
        createdAt: existingCreatedAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      ).toMap(),
    ));
    await _log(AuditActionType.updateStudent, id, AuditLog.entityRagazzo);
  }

Student _normalize(Student student) {
    final noteAllergieSalute =
        student.noteAllergieSalute != null
            ? FieldEncryptionService.encrypt(student.noteAllergieSalute)!
            : '';
    final allergies = _encryptField(student.allergies);
    final autonomousExits = _encryptField(student.autonomousExits);
    final notes = _encryptField(student.notes);
    final studentPhone = _encryptField(student.studentPhone);
    final motherPhone = _encryptField(student.motherPhone);
    final fatherPhone = _encryptField(student.fatherPhone);
    final parentEmail = _encryptField(student.parentEmail);

    return Student(
      id: student.id,
      name: NameFormatting.capitalizeWords(student.name),
      surname: NameFormatting.capitalizeWords(student.surname),
      birthDate: student.birthDate,
      classId: student.classId,
      classUniqueCode: student.classUniqueCode,
      motherName: NameFormatting.capitalizeWords(student.motherName),
      motherSurname: NameFormatting.capitalizeWords(student.motherSurname),
      fatherName: NameFormatting.capitalizeWords(student.fatherName),
      fatherSurname: NameFormatting.capitalizeWords(student.fatherSurname),
      motherPhone: motherPhone ?? '',
      fatherPhone: fatherPhone ?? '',
      studentPhone: studentPhone ?? '',
      parentEmail: parentEmail ?? '',
      consensoPrivacyFirmato: student.consensoPrivacyFirmato,
      dataFirmaConsenso: student.dataFirmaConsenso,
      dataScadenzaTrattamento: student.dataScadenzaTrattamento,
      consensoUsciteAutonome: student.consensoUsciteAutonome,
      contributoVersato: student.contributoVersato,
      contributoEuros: student.contributoEuros,
      annoContributo: student.annoContributo,
      noteAllergieSalute: noteAllergieSalute,
      allergies: allergies,
      autonomousExits: autonomousExits,
      notes: notes,
      statoPercorso: student.statoPercorso,
      annoIscrizione: student.annoIscrizione,
      sacraments: student.sacraments,
    );
  }

  String? _encryptField(String? value) {
    if (value != null && value.isNotEmpty) {
      return FieldEncryptionService.encrypt(value);
    }
    return null;
  }

  /// Cerca il codice univoco di 40 cifre a partire dal [classId].
  String? _lookupClassUniqueCode(String? classId) {
    if (classId == null || classId.isEmpty) return null;
    final classData = LocalDatabase.classes().get(classId);
    if (classData == null) return null;
    final map = LocalDatabase.toStringDynamicMap(classData);
    return map['uniqueCode'] as String?;
  }

  /// Aggiorna lo stato del percorso (ATTIVO/FERMO/RITIRATO) di uno studente.
  Future<void> setStatoPercorso(String id, String stato) async {
    final existing = getAllStudentsSync().where((s) => s.id == id).firstOrNull;
    if (existing == null) return;
    await updateStudent(id, existing.copyWith(statoPercorso: stato));
  }

  /// Aggiorna l'anno di iscrizione di uno studente.
  Future<void> setAnnoIscrizione(String id, String anno) async {
    final existing = getAllStudentsSync().where((s) => s.id == id).firstOrNull;
    if (existing == null) return;
    await updateStudent(id, existing.copyWith(annoIscrizione: anno));
  }

  /// Aggiorna l'elenco dei sacramenti ricevuti da uno studente.
  Future<void> setSacraments(String id, List<Sacrament> sacraments) async {
    final existing = getAllStudentsSync().where((s) => s.id == id).firstOrNull;
    if (existing == null) return;
    await updateStudent(id, existing.copyWith(sacraments: sacraments));
  }

  /// Rimuove uno studente dalla classe, liberando classId e aggiornando
  /// la classe (mantiene lo studente in anagrafica, non lo cancella).
  Future<void> removeFromClass(String studentId, String classId) async {
    final existing = getAllStudentsSync().where((s) => s.id == studentId).firstOrNull;
    if (existing == null) return;
    final isCurrent = existing.classId == classId;
    await updateStudent(studentId, Student(
      id: existing.id,
      name: existing.name,
      surname: existing.surname,
      birthDate: existing.birthDate,
      classId: isCurrent ? null : existing.classId,
      classUniqueCode: isCurrent ? null : existing.classUniqueCode,
      motherName: existing.motherName,
      motherSurname: existing.motherSurname,
      fatherName: existing.fatherName,
      fatherSurname: existing.fatherSurname,
      motherPhone: existing.motherPhone,
      fatherPhone: existing.fatherPhone,
      studentPhone: existing.studentPhone,
      parentEmail: existing.parentEmail,
      allergies: existing.allergies,
      autonomousExits: existing.autonomousExits,
      notes: existing.notes,
      consensoPrivacyFirmato: existing.consensoPrivacyFirmato,
      dataFirmaConsenso: existing.dataFirmaConsenso,
      dataScadenzaTrattamento: existing.dataScadenzaTrattamento,
      consensoUsciteAutonome: existing.consensoUsciteAutonome,
      contributoVersato: existing.contributoVersato,
      contributoEuros: existing.contributoEuros,
      annoContributo: existing.annoContributo,
      noteAllergieSalute: existing.noteAllergieSalute,
      statoPercorso: existing.statoPercorso,
      annoIscrizione: existing.annoIscrizione,
      sacraments: existing.sacraments,
    ));
    final classesBox = LocalDatabase.classes();
    for (final classKey in classesBox.keys) {
      final data = LocalDatabase.toStringDynamicMap(classesBox.get(classKey));
      final studentIds = (data['studentIds'] as List? ?? [])
          .map((value) => value.toString())
          .where((sId) => sId != studentId)
          .toList();
      data['studentIds'] = studentIds;
      await classesBox.put(classKey, data);
    }
  }

  Future<void> deleteStudent(String id) async {
    await AttachmentsRepository().deleteAllForParent(
      parentId: id,
      parentType: AttachmentParentType.student,
    );
    await StudentDailyNotesRepository().deleteAllForStudent(id);
    await _box.delete(id);
    await HistoricalRecordRepository().deleteRecordsForStudent(id);

    final classesBox = LocalDatabase.classes();
    for (final classKey in classesBox.keys) {
      final data = LocalDatabase.toStringDynamicMap(classesBox.get(classKey));
      final studentIds = (data['studentIds'] as List? ?? [])
          .map((value) => value.toString())
          .where((studentId) => studentId != id)
          .toList();
      data['studentIds'] = studentIds;
      await classesBox.put(classKey, data);
    }

    final attendanceBox = LocalDatabase.attendance();
    for (final attendanceKey in attendanceBox.keys) {
      final data = LocalDatabase.toStringDynamicMap(attendanceBox.get(attendanceKey));
      final presence = Map<String, dynamic>.from(data['presence'] as Map? ?? {});
      if (presence.remove(id) != null) {
        data['presence'] = presence;
        await attendanceBox.put(attendanceKey, data);
      }
    }

    final deliveriesBox = LocalDatabase.documentDeliveries();
    for (final deliveryKey in deliveriesBox.keys) {
      final data = LocalDatabase.toStringDynamicMap(deliveriesBox.get(deliveryKey));
      if (data.remove(id) != null) {
        await deliveriesBox.put(deliveryKey, data);
      }
    }

    await _log(AuditActionType.deleteStudentHard, id, AuditLog.entityRagazzo);
  }

  /// Registra l'azione nel Registro Trattamenti GDPR in modalità best-effort:
  /// un eventuale errore di firma/log non deve mai bloccare l'operazione.
  Future<void> _log(
    AuditActionType action,
    String entityId,
    String entityType,
  ) async {
    try {
      await AuditLogRepository().record(
        actionType: action,
        affectedEntityId: entityId,
        affectedEntityType: entityType,
      );
    } catch (e) {
      // Non bloccante: il log GDPR non deve interrompere le operazioni CRUD.
      if (kDebugMode) {
        debugPrint('[StudentsRepository] AuditLog non registrato ($action): $e');
      }
    }
  }
}


