import '../../core/auth/auth_service.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models/audit_action.dart';
import '../../shared/models/audit_log.dart';
import '../../shared/models/aula.dart';
import '../../shared/models/avviso_template_model.dart';
import '../../shared/models/catechesi_model.dart';
import '../../shared/models/catechist_profile.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/contact_note_model.dart';
import '../../shared/models/parish_config.dart';
import '../../shared/models/planning_meeting.dart';
import '../../shared/models/student_model.dart';
import '../../shared/utils/auth_utils.dart';

class DemoGuideService {
  DemoGuideService._();

  static const guidePendingKey = 'guide_pending';
  static const demoDataActiveKey = 'demo_data_active';
  static const _demoTag = '_demo';

  static const String _responsabileModeKey = 'setup_mode';
  static const String _joinValue = 'join';

  static bool isGuidePending() {
    try {
      return LocalDatabase.auth().get(guidePendingKey, defaultValue: false) as bool;
    } catch (_) {
      return false;
    }
  }

  static Future<void> scheduleGuide() async {
    await LocalDatabase.auth().put(guidePendingKey, true);
  }

  static Future<void> completeGuide() async {
    await LocalDatabase.auth().put(guidePendingKey, false);
  }

  static bool isDemoDataActive() {
    try {
      return LocalDatabase.auth().get(demoDataActiveKey, defaultValue: false) as bool;
    } catch (_) {
      return false;
    }
  }

  static bool isJoinedMode() {
    try {
      return LocalDatabase.auth().get(_responsabileModeKey, defaultValue: 'create') == _joinValue;
    } catch (_) {
      return false;
    }
  }

  static Future<void> handleAppStart() async {
    try {
      if (!isDemoDataActive()) return;
      await purgeDemoData();
      await LocalDatabase.auth().put(demoDataActiveKey, false);
      await LocalDatabase.auth().put(guidePendingKey, false);
    } catch (_) {}
  }

  static Future<void> seedGuideData({required bool isResponsabile}) async {
    if (isResponsabile) {
      await _seedResponsabile();
      await LocalDatabase.auth().put(demoDataActiveKey, true);
    } else if (!isJoinedMode()) {
      await _seedCatechistClass();
      await LocalDatabase.auth().put(demoDataActiveKey, true);
    }
  }

  static Future<void> purgeDemoData() async {
    final studentBox = LocalDatabase.students();
    final classBox = LocalDatabase.classes();
    final planningBox = LocalDatabase.planning();
    final attendanceBox = LocalDatabase.attendance();
    final documentsBox = LocalDatabase.documents();
    final deliveriesBox = LocalDatabase.documentDeliveries();
    final contactNotesBox = LocalDatabase.contactNotes();
    final avvisiBox = LocalDatabase.avvisi();
    final catechesiBox = LocalDatabase.catechesi();
    final catechistsBox = LocalDatabase.catechists();
    final aulaBox = LocalDatabase.aula();
    final auditLogBox = LocalDatabase.auditLog();

    final demoStudentIds = <String>{};
    for (final key in studentBox.keys.toList()) {
      final data = LocalDatabase.toStringDynamicMap(studentBox.get(key));
      if (data[_demoTag] == true) {
        demoStudentIds.add(key.toString());
        await studentBox.delete(key);
      }
    }

    for (final key in classBox.keys.toList()) {
      final data = LocalDatabase.toStringDynamicMap(classBox.get(key));
      if (data[_demoTag] == true) {
        await classBox.delete(key);
        continue;
      }
      final studentIds = (data['studentIds'] as List? ?? [])
          .map((e) => e.toString())
          .toList();
      final filtered = studentIds.where((id) => !demoStudentIds.contains(id)).toList();
      if (filtered.length != studentIds.length) {
        data['studentIds'] = filtered;
        data['updatedAt'] = DateTime.now().toIso8601String();
        await classBox.put(key, data);
      }
    }

    for (final box in [
      planningBox,
      attendanceBox,
      documentsBox,
      deliveriesBox,
      contactNotesBox,
      avvisiBox,
      catechesiBox,
      catechistsBox,
      aulaBox,
      auditLogBox,
    ]) {
      for (final key in box.keys.toList()) {
        final raw = box.get(key);
        final data = LocalDatabase.toStringDynamicMap(raw);
        if (data[_demoTag] == true) {
          await box.delete(key);
        }
      }
    }

    try {
      final configBox = LocalDatabase.parishConfig();
      final raw = configBox.get(ParishConfig.storageKey);
      final data = LocalDatabase.toStringDynamicMap(raw);
      if (data[_demoTag] == true) {
        await configBox.delete(ParishConfig.storageKey);
      }
    } catch (_) {}
  }

  static Map<String, dynamic> _tagged(Map<String, dynamic> map) {
    return {...map, _demoTag: true};
  }

  static Future<void> _seedCatechistClass() async {
    final classBox = LocalDatabase.classes();
    final studentBox = LocalDatabase.students();
    final planningBox = LocalDatabase.planning();
    final attendanceBox = LocalDatabase.attendance();
    final documentsBox = LocalDatabase.documents();
    final contactNotesBox = LocalDatabase.contactNotes();
    final avvisiBox = LocalDatabase.avvisi();
    final catechesiBox = LocalDatabase.catechesi();

    final currentClassId = LocalDatabase.auth().get('current_class_id') as String?;
    if (currentClassId == null || currentClassId.isEmpty) return;
    final classRaw = classBox.get(currentClassId);
    if (classRaw == null) return;

    final classData = LocalDatabase.toStringDynamicMap(classRaw);
    final classUniqueCode = classData['uniqueCode']?.toString() ?? '';
    final operator = getCurrentCatechistName();

    final demoIds = <String>[];
    final students = <Student>[];
    final names = [
      (name: 'Luca', surname: 'Bianchi', birth: '2015-03-12', allergy: 'Nichel'),
      (name: 'Sofia', surname: 'Romano', birth: '2014-07-01', allergy: null),
      (name: 'Matteo', surname: 'Ferrari', birth: '2015-11-23', allergy: 'Glutine'),
      (name: 'Giulia', surname: 'Esposito', birth: '2014-02-18', allergy: null),
      (name: 'Davide', surname: 'Conti', birth: '2015-09-05', allergy: null),
      (name: 'Chiara', surname: 'Marino', birth: '2014-12-14', allergy: 'Lattosio'),
    ];
    final now = DateTime.now();
    for (var i = 0; i < names.length; i++) {
      final n = names[i];
      final id = LocalDatabase.newId('student');
      demoIds.add(id);
      final student = Student(
        id: id,
        name: n.name,
        surname: n.surname,
        birthDate: DateTime.parse(n.birth),
        classId: currentClassId,
        classUniqueCode: classUniqueCode,
        motherName: 'Giulia',
        motherSurname: n.surname,
        fatherName: 'Marco',
        fatherSurname: n.surname,
        motherPhone: '333 10${100000 + i * 7}',
        fatherPhone: '335 10${100000 + i * 7}',
        studentPhone: '',
        parentEmail: 'genitore${i + 1}@esempio.it',
        allergies: n.allergy,
        autonomousExits: i % 3 == 0 ? 'Permesso di uscita firmato' : null,
        consensoPrivacyFirmato: true,
        dataFirmaConsenso: now.subtract(const Duration(days: 30)),
        dataScadenzaTrattamento: now.add(const Duration(days: 335)),
        consensoUsciteAutonome: i % 2 == 0,
        contributoVersato: i % 4 == 0,
        contributoEuros: i % 4 == 0 ? 5.0 : 0,
        annoContributo: '${now.year}-${now.year + 1}',
        statoPercorso: 'ATTIVO',
        annoIscrizione: '${now.year}-${now.year + 1}',
        lastModifiedBy: operator,
      );
      students.add(student);
      await studentBox.put(id, _tagged(student.toMap()));
    }

    final updatedClass = Map<String, dynamic>.from(classData);
    final existingIds = (updatedClass['studentIds'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    updatedClass['studentIds'] = [...existingIds, ...demoIds];
    updatedClass['updatedAt'] = now.toIso8601String();
    await classBox.put(currentClassId, updatedClass);

    final meetings = <(PlanningMeeting, Map<String, String>)>[];
    final pastMeetings = <(String, String)>[
      ('Incontro sulla Pasqua', 'Racconto della risurrezione e attività di gruppo'),
      ('La parabola del buon samaritano', 'Lettura dal Vangelo di Luca e disegno'),
      ('Giornata della carità', 'Preparazione delle buste di carità per la domenica'),
    ];
    for (var i = 0; i < pastMeetings.length; i++) {
      final (title, activity) = pastMeetings[i];
      final date = now.subtract(Duration(days: 28 - i * 7));
      final meeting = PlanningMeeting(
        id: LocalDatabase.newId('meeting'),
        classId: currentClassId,
        classUniqueCode: classUniqueCode,
        createdBy: AuthService.localUserId,
        date: DateTime(date.year, date.month, date.day, 16, 0),
        title: title,
        activity: activity,
        notes: 'Appello e attività conclusa.',
        lastModifiedBy: operator,
      );
      final presence = <String, String>{
        for (final s in students) s.id: (s.id.hashCode % 5 == 0 ? 'Assente' : 'Presente'),
      };
      meetings.add((meeting, presence));
    }
    final upcoming = PlanningMeeting(
      id: LocalDatabase.newId('meeting'),
      classId: currentClassId,
      classUniqueCode: classUniqueCode,
      createdBy: AuthService.localUserId,
      date: DateTime(now.year, now.month, now.day, 16, 0).add(const Duration(days: 7)),
      title: 'Preparazione alla Messa',
      activity: 'Prove delle letture e canti',
      notes: 'Portare i foglietti preparati.',
      lastModifiedBy: operator,
    );

    for (final (meeting, presence) in meetings) {
      await planningBox.put(meeting.id, _tagged(meeting.toMap()));
      await attendanceBox.put(
        meeting.id,
        _tagged({
          'meetingId': meeting.id,
          'date': meeting.date.toIso8601String(),
          'classId': currentClassId,
          'classUniqueCode': classUniqueCode,
          'presence': presence,
        }),
      );
    }
    await planningBox.put(upcoming.id, _tagged(upcoming.toMap()));

    final documents = [
      'Autorizzazione uscita al Parco',
      'Modulo consenso fotografie',
    ];
    for (final title in documents) {
      await documentsBox.put(
        LocalDatabase.newId('document'),
        _tagged({
          'title': title,
          'classUniqueCode': classUniqueCode,
          'createdAt': now.subtract(const Duration(days: 10)).toIso8601String(),
          'updatedAt': now.toIso8601String(),
          'lastModifiedBy': operator,
        }),
      );
    }

    for (var i = 0; i < 2; i++) {
      final student = students[i];
      await contactNotesBox.put(
        LocalDatabase.newId('note'),
        _tagged(ContactNote(
          id: LocalDatabase.newId('note'),
          studentId: student.id,
          classUniqueCode: classUniqueCode,
          dateTime: now.subtract(Duration(days: 5 + i * 2)),
          medium: i == 0 ? 'whatsapp' : 'de_visu',
          notes: i == 0
              ? 'Contattata la mamma per comunicare l\'assenza di ${student.name}.'
              : 'Incontro a fine Messa con i genitori di ${student.name}.',
          lastModifiedBy: operator,
        ).toMap()),
      );
    }

    final avvisi = [
      ('Avviso di assenze consecutive', 'Caro/a {nome_genitore},\n\n{assenze_consecutive} assenze consecutive di {nome_ragazzo} sono state registrate in {nome_gruppo}. Il prossimo incontro è il {data_incontro}.'),
      ('Avviso incontro di catechismo', 'Caro/a {nome_genitore},\n\nil prossimo incontro di {nome_gruppo} è fissato per il {data_incontro}. Grazie per la collaborazione.'),
    ];
    for (final (title, text) in avvisi) {
      await avvisiBox.put(
        LocalDatabase.newId('avviso'),
        _tagged(AvvisoTemplate(
          id: LocalDatabase.newId('avviso'),
          classUniqueCode: classUniqueCode,
          title: title,
          text: text,
        ).toMap()),
      );
    }

    final catechesi = [
      ('La parabola del buon samaritano', ['Vangelo', 'Parabole'], ['Lc 10,25-37'],
          'Chi è il mio prossimo? Storia di compassione e misericordia.'),
      ('Le Beatitudini', ['Vangelo'], ['Mt 5,1-12'],
          'Il discorso della montagna: le promesse di Gesù per chi lo segue.'),
      ('Il Padre Nostro', ['Preghiera'], ['Mt 6,9-13'],
          'La preghiera che Gesù insegna ai discepoli.'),
    ];
    for (final (title, tags, refs, description) in catechesi) {
      final catechesi = Catechesi(
        id: LocalDatabase.newId('catechesi'),
        classUniqueCode: classUniqueCode,
        title: title,
        tags: tags,
        biblicalReferences: refs,
        websiteReferences: const [],
        photoIds: const [],
        description: description,
        createdAt: now,
        updatedAt: now,
        lastModifiedBy: operator,
      );
      await catechesiBox.put(catechesi.id, _tagged(catechesi.toMap()));
    }
  }

  static Future<void> _seedResponsabile() async {
    final configBox = LocalDatabase.parishConfig();
    final classBox = LocalDatabase.classes();
    final studentBox = LocalDatabase.students();
    final planningBox = LocalDatabase.planning();
    final attendanceBox = LocalDatabase.attendance();
    final catechistsBox = LocalDatabase.catechists();
    final aulaBox = LocalDatabase.aula();
    final auditLogBox = LocalDatabase.auditLog();

    final operator = getCurrentCatechistName();
    final operatorId = AuthService.getCatechistId();
    final now = DateTime.now();
    final anno = '${now.year}-${now.year + 1}';

    final config = ParishConfig(
      isResponsabileModeActive: true,
      nomeParrocchia: 'Parrocchia San Francesco d\'Assisi',
      diocesi: 'Diocesi di Roma',
      annoCatechisticoCorrente: anno,
      durataValiditaConsensoMesi: 12,
      sogliaAssenzeConsecutive: 3,
    );
    await configBox.put(ParishConfig.storageKey, _tagged(config.toMap()));

    final catechists = <CatechistProfile>[];
    final catechistNames = [
      ('Maria', 'Rossi'),
      ('Giuseppe', 'Verdi'),
      ('Anna', 'Bianchi'),
      ('Paolo', 'Neri'),
    ];
    for (var i = 0; i < catechistNames.length; i++) {
      final (firstName, lastName) = catechistNames[i];
      final id = 'cat_demo_${i + 1}';
      final profile = CatechistProfile(
        id: id,
        firstName: firstName,
        lastName: lastName,
        phone: '349 1${i}2 3${i}4 5$i',
      );
      catechists.add(profile);
      await catechistsBox.put(id, _tagged(profile.toMap()));
    }

    final aulas = <Aula>[];
    final aulaNames = [
      ('Aula San Giuseppe', 20, 'Piano terra, accessibile'),
      ('Sala parrocchiale', 40, 'Primo piano'),
      ('Cappella', 10, 'Accesso con gradino'),
    ];
    for (var i = 0; i < aulaNames.length; i++) {
      final (name, capienza, note) = aulaNames[i];
      final id = LocalDatabase.newId('stanza');
      final aula = Aula(
        stanzaId: id,
        nomeStanza: name,
        capienzaMassima: capienza,
        noteAccessibilita: note,
        lastModifiedBy: operator,
      );
      aulas.add(aula);
      await aulaBox.put(id, _tagged(aula.toMap()));
    }

    final classDefs = [
      (name: 'Prima Comunione - 1° anno', percorso: 'Prima Comunione', livello: 1),
      (name: 'Prima Comunione - 2° anno', percorso: 'Prima Comunione', livello: 2),
      (name: 'Cresima - 1° anno', percorso: 'Cresima', livello: 1),
      (name: 'Cresima - 2° anno', percorso: 'Cresima', livello: 2),
    ];
    final studentNames = [
      ('Luca', 'Bianchi', 0),
      ('Sofia', 'Romano', 0),
      ('Matteo', 'Ferrari', 1),
      ('Giulia', 'Esposito', 1),
      ('Davide', 'Conti', 2),
      ('Chiara', 'Marino', 2),
      ('Federico', 'Gallo', 3),
      ('Martina', 'Rizzi', 3),
    ];

    final classRecords = <String, Map<String, dynamic>>{};
    final classStudents = <String, List<Student>>{};

    for (var i = 0; i < classDefs.length; i++) {
      final def = classDefs[i];
      final classId = LocalDatabase.newId('class');
      final slot = RoomSlot(
        slotId: LocalDatabase.newId('slot'),
        stanzaId: aulas[i % aulas.length].stanzaId,
        nomeStanza: aulas[i % aulas.length].nomeStanza,
        giornoSettimana: 2 + (i % 4),
        oraInizio: '15:30',
        oraFine: '17:00',
        note: 'Demo',
      );
      final lead = catechists[i % catechists.length];
      final helper = catechists[(i + 1) % catechists.length];
      final schoolClass = SchoolClass(
        id: classId,
        name: def.name,
        studentIds: const [],
        catechistIds: [lead.id, helper.id],
        lastModifiedBy: operator,
        uniqueCode: generateClassUniqueCode(),
        creatorId: operatorId,
        creatorName: operator,
        creatorCatechistId: operatorId,
        associatedCatechistIds: [helper.id],
        catechistDeviceCounts: {lead.id: 1, helper.id: 1},
        percorso: def.percorso,
        livello: def.livello,
        annoCatechistico: anno,
        archived: false,
        catechistRoles: {lead.id: 'TITOLARE', helper.id: 'AIUTO'},
        roomSlots: [slot],
      );
      final map = _tagged(schoolClass.toMap());
      map['studentIds'] = <String>[];
      await classBox.put(classId, map);
      classRecords[classId] = map;
      classStudents[classId] = [];

      await auditLogBox.put(
        generateAuditLogUuidV4(),
        _tagged(AuditLog(
          logId: generateAuditLogUuidV4(),
          timestamp: now.subtract(Duration(days: 20 - i)),
          actionType: AuditActionType.createClass,
          executedByCatechistId: operatorId,
          executedByCatechistName: operator,
          affectedEntityType: AuditLog.entityClasse,
          affectedEntityId: classId,
        ).toMap()),
      );
    }

    final ids = classRecords.keys.toList();
    for (var i = 0; i < studentNames.length; i++) {
      final (name, surname, classIdx) = studentNames[i];
      final classId = ids[classIdx];
      final classUniqueCode = classRecords[classId]!['uniqueCode']?.toString() ?? '';
      final id = LocalDatabase.newId('student');
      final student = Student(
        id: id,
        name: name,
        surname: surname,
        birthDate: DateTime(2013 + (i % 3), 1 + (i % 12), 1 + (i % 27)),
        classId: classId,
        classUniqueCode: classUniqueCode,
        motherName: 'Giulia',
        motherSurname: surname,
        fatherName: 'Marco',
        fatherSurname: surname,
        motherPhone: '333 12${i}4567',
        fatherPhone: '335 12${i}4568',
        studentPhone: '',
        parentEmail: 'famiglia${i + 1}@esempio.it',
        allergies: i % 4 == 0 ? 'Allergia al nichel' : null,
        consensoPrivacyFirmato: i % 5 != 3,
        dataFirmaConsenso: i % 5 != 3 ? now.subtract(const Duration(days: 15)) : null,
        consensoUsciteAutonome: i % 2 == 0,
        contributoVersato: i % 3 == 0,
        statoPercorso: 'ATTIVO',
        annoIscrizione: anno,
        lastModifiedBy: operator,
      );
      await studentBox.put(id, _tagged(student.toMap()));
      classStudents[classId]!.add(student);
      final map = classRecords[classId]!;
      map['studentIds'] = [id, ...(map['studentIds'] as List).cast<String>()];
      await classBox.put(classId, map);

      await auditLogBox.put(
        generateAuditLogUuidV4(),
        _tagged(AuditLog(
          logId: generateAuditLogUuidV4(),
          timestamp: now.subtract(Duration(days: 14 - i % 5)),
          actionType: i % 5 == 3 ? AuditActionType.grantConsent : AuditActionType.createStudent,
          executedByCatechistId: operatorId,
          executedByCatechistName: operator,
          affectedEntityType: i % 5 == 3 ? AuditLog.entityConsenso : AuditLog.entityRagazzo,
          affectedEntityId: id,
        ).toMap()),
      );
    }

    for (final classId in ids) {
      final map = classRecords[classId]!;
      final uniqueCode = map['uniqueCode']?.toString() ?? '';
      final students = classStudents[classId]!;
      if (students.isEmpty) continue;
      for (var i = 0; i < 2; i++) {
        final date = now.subtract(Duration(days: 21 - i * 7));
        final meeting = PlanningMeeting(
          id: LocalDatabase.newId('meeting'),
          classId: classId,
          classUniqueCode: uniqueCode,
          createdBy: operatorId,
          date: DateTime(date.year, date.month, date.day, 16, 0),
          title: i == 0 ? 'Incontro di catechismo' : 'Riunione con i catechisti',
          activity: 'Attività sul Vangelo della domenica',
          notes: 'Demo',
          isReunion: i == 1,
          lastModifiedBy: operator,
        );
        await planningBox.put(meeting.id, _tagged(meeting.toMap()));
        if (!meeting.isReunion) {
          await attendanceBox.put(
            meeting.id,
            _tagged({
              'meetingId': meeting.id,
              'date': meeting.date.toIso8601String(),
              'classId': classId,
              'classUniqueCode': uniqueCode,
              'presence': {
                for (final s in students)
                  s.id: (s.id.hashCode % 5 == 0 ? 'Assente' : 'Presente'),
              },
            }),
          );
        }
      }
    }
  }
}
