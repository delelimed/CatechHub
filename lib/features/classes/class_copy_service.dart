import 'package:hive/hive.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/planning_meeting.dart';
import '../../shared/models/catechesi_model.dart';
import '../../shared/models/avviso_template_model.dart';
import '../../shared/utils/auth_utils.dart';

/// Risultato di un'operazione di copia tra classi.
class ClassCopyResult {
  final int documents;
  final int catechesi;
  final int avvisi;
  final int meetings;
  final int catechesiAssociations;

  const ClassCopyResult({
    this.documents = 0,
    this.catechesi = 0,
    this.avvisi = 0,
    this.meetings = 0,
    this.catechesiAssociations = 0,
  });

  bool get isEmpty =>
      documents == 0 && catechesi == 0 && avvisi == 0 && meetings == 0;

  int get totalItems => documents + catechesi + avvisi + meetings;
}

/// Servizio per copiare contenuti da una classe sorgente alla classe corrente.
///
/// Copia SOLO i contenuti (documenti, catechesi, messaggi programmati,
/// calendario) senza portare con sé le associazioni ai ragazzi:
/// - i documenti vengono copiati come nuovi record SENZA le consegne per studente;
/// - le catechesi vengono copiate come nuovi record;
/// - gli avvisi (messaggi programmati) vengono copiati come nuovi template;
/// - gli incontri del calendario vengono copiati come nuovi incontri della
///   classe corrente, SENZA l'eventuale registro presenze;
///
/// Le associazioni incontro-catechesi (box [meetingCatechesiBox]) vengono
/// ricreate assegnandole ai NUOVI incontri e alle NUOVE catechesi copiate.
class ClassCopyService {
  /// Copia i contenuti selezionati dalla classe [sourceClass] verso
  /// [targetClass].
  ///
  /// - [includeDocuments]: copia i documenti della classe sorgente.
  /// - [includeCatechesi]: copia le catechesi della classe sorgente.
  /// - [includeAvvisi]: copia i messaggi programmati della classe sorgente.
  /// - [includeCalendar]: copia gli incontri della classe sorgente.
  ///
  /// Ritorna un [ClassCopyResult] con i conteggi dei record copiati.
  static Future<ClassCopyResult> copyContent({
    required SchoolClass sourceClass,
    required SchoolClass targetClass,
    required bool includeDocuments,
    required bool includeCatechesi,
    required bool includeAvvisi,
    required bool includeCalendar,
  }) async {
    final catechistName = getCurrentCatechistName();
    final now = DateTime.now().toIso8601String();

    var documents = 0;
    var catechesi = 0;
    var avvisi = 0;
    var meetings = 0;

    final meetingIdMap = <String, String>{};
    final catechesiIdMap = <String, String>{};

    // ─── DOCUMENTI ─────────────────────────────────────────────────────
    if (includeDocuments) {
      final docs = _recordsOfClass(
        LocalDatabase.documents(),
        'classUniqueCode',
        sourceClass.uniqueCode,
      );
      for (final entry in docs) {
        final data = Map<String, dynamic>.from(entry['data'] as Map);
        data['classUniqueCode'] = targetClass.uniqueCode;
        data['lastModifiedBy'] = catechistName;
        data['updatedAt'] = now;
        final newId = LocalDatabase.newId('document');
        await LocalDatabase.documents().put(newId, data);
        documents++;
      }
    }

    // ─── CATECHESI ─────────────────────────────────────────────────────
    if (includeCatechesi) {
      final catechesiList = _getCatechesiByClassSync(sourceClass.uniqueCode);
      for (final c in catechesiList) {
        final newId = LocalDatabase.newId('catechesi');
        final copy = c.copyWith(
          id: newId,
          classUniqueCode: targetClass.uniqueCode,
          lastModifiedBy: catechistName,
        );
        await LocalDatabase.catechesi().put(
          newId,
          copy.toMap()
            ..['createdAt'] = now
            ..['updatedAt'] = now,
        );
        catechesiIdMap[c.id] = newId;
        catechesi++;
      }
    }

    // ─── AVVISI (MESSAGGI PROGRAMMATI) ─────────────────────────────────
    if (includeAvvisi) {
      final avvisiList = _getAvvisiByClassSync(sourceClass.uniqueCode);
      for (final a in avvisiList) {
        final newId = LocalDatabase.newId('avviso_template');
        final copy = a.copyWith(
          id: newId,
          classUniqueCode: targetClass.uniqueCode,
        );
        await LocalDatabase.avvisi().put(newId, copy.toMap());
        avvisi++;
      }
    }

    // ─── CALENDARIO (INCONTRI) ─────────────────────────────────────────
    if (includeCalendar) {
      final meetingList = _getPlanningByClassSync(sourceClass.id);
      for (final meeting in meetingList) {
        final newId = LocalDatabase.newId('meeting');
        final copy = meeting.copyWith(
          id: newId,
          classId: targetClass.id,
          classUniqueCode: targetClass.uniqueCode,
          lastModifiedBy: catechistName,
        );
        await LocalDatabase.planning().put(
          newId,
          copy.toMap()
            ..['createdAt'] = now
            ..['updatedAt'] = now,
        );
        meetingIdMap[meeting.id] = newId;
        meetings++;
      }
    }

    // ─── ASSOCIAZIONI INCONTRO-CATECHESI ───────────────────────────────
    var catechesiAssociations = 0;
    if (includeCalendar) {
      catechesiAssociations = await _copyMeetingCatechesi(
        meetingIdMap: meetingIdMap,
        catechesiIdMap: catechesiIdMap,
      );
    }

    return ClassCopyResult(
      documents: documents,
      catechesi: catechesi,
      avvisi: avvisi,
      meetings: meetings,
      catechesiAssociations: catechesiAssociations,
    );
  }

  // ─── HELPER LETTURA ─────────────────────────────────────────────────

  /// Legge i record di un box filtrati sul campo [field] == [value].
  static List<Map<String, dynamic>> _recordsOfClass(
    Box box,
    String field,
    String value,
  ) {
    final result = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      final data = LocalDatabase.toStringDynamicMap(box.get(key));
      if (data[field]?.toString() == value) {
        result.add({'id': key.toString(), 'data': data});
      }
    }
    return result;
  }

  static List<Catechesi> _getCatechesiByClassSync(String classUniqueCode) {
    return _recordsOfClass(
          LocalDatabase.catechesi(),
          'classUniqueCode',
          classUniqueCode,
        )
        .map(
          (e) => Catechesi.fromMap(
            e['id'] as String,
            e['data'] as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  static List<AvvisoTemplate> _getAvvisiByClassSync(String classUniqueCode) {
    return _recordsOfClass(
          LocalDatabase.avvisi(),
          'classUniqueCode',
          classUniqueCode,
        )
        .map(
          (e) => AvvisoTemplate.fromMap(
            e['id'] as String,
            e['data'] as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  static List<PlanningMeeting> _getPlanningByClassSync(String classId) {
    final result = <PlanningMeeting>[];
    final box = LocalDatabase.planning();
    for (final key in box.keys) {
      final data = LocalDatabase.toStringDynamicMap(box.get(key));
      if (data['classId']?.toString() == classId) {
        result.add(PlanningMeeting.fromMap(key.toString(), data));
      }
    }
    return result;
  }

  static Future<int> _copyMeetingCatechesi({
    required Map<String, String> meetingIdMap,
    required Map<String, String> catechesiIdMap,
  }) async {
    final box = LocalDatabase.meetingCatechesi();
    var count = 0;
    for (final key in box.keys) {
      final newMeetingId = meetingIdMap[key.toString()];
      if (newMeetingId == null) continue;
      final raw = box.get(key);
      final catechesiIds = raw is List
          ? raw.map((e) => e.toString()).toList()
          : <String>[];
      final remapped = catechesiIds.map((id) {
        // Se la catechesi è stata copiata, punta alla nuova; altrimenti
        // mantiene l'id originale (contenuto condiviso).
        return catechesiIdMap[id] ?? id;
      }).toList();
      await box.put(newMeetingId, remapped);
      count++;
    }
    return count;
  }
}
