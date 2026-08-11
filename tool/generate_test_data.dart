import 'dart:io';
import 'dart:math';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:CatechHub/core/auth/auth_service.dart';
import 'package:CatechHub/shared/models/class_model.dart';
import 'package:CatechHub/shared/models/student_model.dart';
import 'package:CatechHub/shared/models/parish_config.dart';
import 'package:CatechHub/shared/models/planning_meeting.dart';
import 'package:CatechHub/shared/models/catechesi_model.dart';
import 'package:CatechHub/shared/models/aula.dart';
import 'package:CatechHub/shared/models/contact_note_model.dart';
import 'package:CatechHub/shared/models/student_daily_note_model.dart';
import 'package:CatechHub/shared/models/avviso_template_model.dart';
import 'package:CatechHub/shared/models/audit_log.dart';
import 'package:CatechHub/shared/models/audit_action.dart';
import 'package:CatechHub/core/services/data_export_service.dart';
import 'package:CatechHub/core/storage/local_database.dart';

// ─── Constants ────────────────────────────────────────────────────────────

const String pin = '12345678';
const int numClasses = 10;
const int studentsPerClass = 15;
const int catechistsPerClass = 2;

final Random _random = Random.secure();

// ─── Fake Data Generators ────────────────────────────────────────────────

const List<String> _firstNames = [
  'Alessandro', 'Giulia', 'Matteo', 'Sofia', 'Lorenzo', 'Aurora', 'Leonardo', 'Ginevra',
  'Francesco', 'Alice', 'Andrea', 'Emma', 'Riccardo', 'Beatrice', 'Edoardo', 'Ludovica',
  'Tommaso', 'Vittoria', 'Gabriele', 'Sara', 'Davide', 'Chiara', 'Samuele', 'Martina',
  'Pietro', 'Greta', 'Nicolò', 'Elena', 'Federico', 'Anna', 'Daniele', 'Laura',
  'Simone', 'Francesca', 'Cristian', 'Giada', 'Emanuele', 'Noemi', 'Michele', 'Rebecca',
  'Antonio', 'Camilla', 'Giuseppe', 'Asia', 'Salvatore', 'Giorgia', 'Luca', 'Arianna',
];

const List<String> _lastNames = [
  'Rossi', 'Ferrari', 'Russo', 'Bianchi', 'Romano', 'Gallo', 'Costa', 'Fontana',
  'Conti', 'Esposito', 'Ricci', 'Bruno', 'De Luca', 'Moretti', 'Marino', 'Greco',
  'Barbieri', 'Lombardi', 'Giordano', 'Rizzo', 'De Santis', 'Colombo', 'Mancini', 'Leone',
  'Martini', 'Caruso', 'Longo', 'Gatti', 'Mariani', 'Ferrara', 'Serra', 'Rinaldi',
  'Benedetti', 'Parisi', 'Vitale', 'Sala', 'Pellegrini', 'Coppola', 'De Angelis', 'Monti',
  'Santoro', 'Marchetti', 'Farina', 'Leone', 'Mazza', 'Riva', 'Donati', 'Bianco',
];

const List<String> _motherFirstNames = [
  'Maria', 'Anna', 'Giulia', 'Francesca', 'Laura', 'Sara', 'Elena', 'Chiara',
  'Paola', 'Silvia', 'Claudia', 'Valentina', 'Martina', 'Alessandra', 'Federica', 'Cristina',
];

const List<String> _fatherFirstNames = [
  'Marco', 'Luca', 'Andrea', 'Matteo', 'Stefano', 'Davide', 'Alessandro', 'Francesco',
  'Antonio', 'Giuseppe', 'Roberto', 'Simone', 'Fabio', 'Claudio', 'Emanuele', 'Riccardo',
];

const List<String> _classNames = [
  'Prima Elementare', 'Seconda Elementare', 'Terza Elementare', 'Quarta Elementare', 'Quinta Elementare',
  'Prima Media', 'Seconda Media', 'Terza Media',
  'Prima Comunione 1° Anno', 'Prima Comunione 2° Anno',
  'Cresima 1° Anno', 'Cresima 2° Anno',
];

const List<String> _percorsi = [
  'Prima Comunione', 'Cresima', 'Post-Cresima', 'Iniziazione Cristiana',
];

const List<String> _allergies = [
  '', '', '', '', '', // Most have no allergies
  'Arachidi', 'Latte e derivati', 'Glutine', 'Uova', 'Frutta a guscio',
  'Pesce', 'Crostacei', 'Soia', 'Sedano', 'Senape',
  'Sesamo', 'Anidride solforosa', 'Lupini', 'Molluschi',
];

const List<String> _autonomousExits = [
  'No', 'No', 'No', 'Sì - solo con autorizzazione scritta', 'Sì - autonomo',
];

const List<String> _notes = [
  '', '', '', '', '', // Most have no notes
  'Molto partecipativo durante le lezioni',
  'Timido all\'inizio ma poi si apre',
  'Ha difficoltà a stare fermo',
  'Ottima memoria per le preghiere',
  'Chiede spesso spiegazioni approfondite',
  'Aiuta i compagni in difficoltà',
  'Porta sempre il materiale',
  'A volte distratto dal cellulare',
  'Molto sensibile alle tematiche sociali',
];

const List<String> _catechesiTitles = [
  'La parabola del buon samaritano',
  'Il battesimo di Gesù',
  'La moltiplicazione dei pani e dei pesci',
  'La resurrezione di Lazzaro',
  'L\'ultima cena',
  'La passione e morte di Gesù',
  'La risurrezione',
  'La pentecoste',
  'I dieci comandamenti',
  'Le beatitudini',
  'Il Padre Nostro',
  'La confessione',
  'L\'Eucaristia',
  'Lo Spirito Santo',
  'Maria, madre di Gesù',
  'I sacramenti',
  'La Chiesa',
  'La carità cristiana',
  'Il perdono',
  'La preghiera',
];

const List<List<String>> _catechesiTags = [
  ['Vangelo', 'Parabole'],
  ['Vangelo', 'Battesimo'],
  ['Vangelo', 'Miracoli'],
  ['Vangelo', 'Miracoli'],
  ['Vangelo', 'Ultima Cena'],
  ['Vangelo', 'Passione'],
  ['Vangelo', 'Resurrezione'],
  ['Vangelo', 'Spirito Santo'],
  ['Antico Testamento', 'Legge'],
  ['Vangelo', 'Beatitudini'],
  ['Preghiera', 'Padre Nostro'],
  ['Sacramenti', 'Riconciliazione'],
  ['Sacramenti', 'Eucaristia'],
  ['Spirito Santo', 'Pentecoste'],
  ['Maria', 'Madre di Dio'],
  ['Sacramenti', 'Catechesi'],
  ['Chiesa', 'Comunità'],
  ['Carità', 'Amore'],
  ['Perdono', 'Riconciliazione'],
  ['Preghiera', 'Spiritualità'],
];

const List<List<String>> _biblicalRefs = [
  ['Lc 10,25-37'],
  ['Mt 3,13-17', 'Mc 1,9-11', 'Lc 3,21-22'],
  ['Mt 14,13-21', 'Mc 6,30-44', 'Lc 9,10-17', 'Gv 6,1-15'],
  ['Gv 11,1-44'],
  ['Mt 26,26-30', 'Mc 14,22-26', 'Lc 22,14-20'],
  ['Mt 27', 'Mc 15', 'Lc 23', 'Gv 19'],
  ['Mt 28', 'Mc 16', 'Lc 24', 'Gv 20'],
  ['At 2,1-13'],
  ['Es 20,2-17', 'Dt 5,6-21'],
  ['Mt 5,1-12'],
  ['Mt 6,9-13', 'Lc 11,1-4'],
  ['Gv 20,22-23'],
  ['Mt 26,26-28', '1Cor 11,23-26'],
  ['Gv 14,15-26', 'At 2'],
  ['Lc 1,26-38', 'Lc 1,46-55'],
  ['CCC 1113-1130'],
  ['CCC 748-780'],
  ['1Cor 13', 'Gv 13,34-35'],
  ['Mt 18,21-35', 'Lc 15,11-32'],
  ['Mt 6,5-15', 'Lc 11,1-13'],
];

const List<List<String>> _websiteRefs = [
  ['https://www.vatican.va', 'https://www.bibbiaedu.it'],
  ['https://www.chiesacattolica.it'],
  ['https://www.francescani.it'],
  ['https://www.salesiani.it'],
  ['https://www.gesuiti.it'],
];

String _randomName() => _firstNames[_random.nextInt(_firstNames.length)];
String _randomSurname() => _lastNames[_random.nextInt(_lastNames.length)];
String _randomMotherName() => _motherFirstNames[_random.nextInt(_motherFirstNames.length)];
String _randomFatherName() => _fatherFirstNames[_random.nextInt(_fatherFirstNames.length)];
String _randomPhone() => '3${_random.nextInt(9)}${_random.nextInt(100000000).toString().padLeft(8, '0')}';
String _randomAllergy() => _allergies[_random.nextInt(_allergies.length)];
String _randomAutonomousExit() => _autonomousExits[_random.nextInt(_autonomousExits.length)];
String _randomNote() => _notes[_random.nextInt(_notes.length)];
DateTime _randomBirthDate(int yearStart, int yearEnd) {
  final year = yearStart + _random.nextInt(yearEnd - yearStart + 1);
  final month = 1 + _random.nextInt(12);
  final day = 1 + _random.nextInt(28);
  return DateTime(year, month, day);
}

String _generateUniqueCode() {
  return List.generate(40, (_) => _random.nextInt(10).toString()).join();
}

String _generateId(String prefix) {
  return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1000000)}';
}

// ─── Main Generation Logic ────────────────────────────────────────────────

Future<void> main() async {
  stdout.writeln('🔧 Initializing Hive...');
  await Hive.initFlutter();
  
  // Generate a secure key for the test database
  final encryptionKey = Hive.generateSecureKey();
  final cipher = HiveAesCipher(encryptionKey);
  
  stdout.writeln('📦 Opening boxes...');
  await LocalDatabase.init(cipher: cipher);
  
  stdout.writeln('🏗️ Generating test data for full parish (10 classes)...');
  await _generateFullParish();
  
  stdout.writeln('📤 Exporting and encrypting full parish data (respo mode)...');
  final fullParishEncrypted = await DataExportService.exportEncryptedData(pin, classId: null);
  await _writeCatechHubFile('respo.catechhub', fullParishEncrypted);
  stdout.writeln('✅ Full parish saved to respo.catechhub');
  
  stdout.writeln('🏗️ Generating test data for single class (norm mode)...');
  await _generateSingleClass();
  
  stdout.writeln('📤 Exporting and encrypting single class data (norm mode)...');
  // Get the first class ID
  final classesBox = LocalDatabase.classes();
  final firstClassKey = classesBox.keys.first;
  final singleClassEncrypted = await DataExportService.exportEncryptedData(pin, classId: firstClassKey.toString());
  await _writeCatechHubFile('norm.catechhub', singleClassEncrypted);
  stdout.writeln('✅ Single class saved to norm.catechhub');
  
  stdout.writeln('\n🎉 Done! Two files created in: ${Directory.current.path}');
  stdout.writeln('   - respo.catechhub (10 classes, 21 catechists, 150 students, responsabile mode ON)');
  stdout.writeln('   - norm.catechhub (1 class, 3 catechists, 15 students, responsabile mode OFF)');
  stdout.writeln('   Both encrypted with pin: $pin');
  
  await Hive.close();
  exit(0);
}

Future<void> _generateFullParish() async {
  // Clear existing data
  await LocalDatabase.classes().clear();
  await LocalDatabase.students().clear();
  await LocalDatabase.planning().clear();
  await LocalDatabase.attendance().clear();
  await LocalDatabase.documents().clear();
  await LocalDatabase.documentDeliveries().clear();
  await LocalDatabase.attachments().clear();
  await LocalDatabase.contactNotes().clear();
  await LocalDatabase.catechesi().clear();
  await LocalDatabase.meetingCatechesi().clear();
  await LocalDatabase.studentDailyNotes().clear();
  await LocalDatabase.aula().clear();
  await LocalDatabase.avvisi().clear();
  await LocalDatabase.auditLog().clear();
  await LocalDatabase.parishConfig().clear();
  
  // Create parish config (responsabile mode ON)
  final parishConfig = ParishConfig(
    isResponsabileModeActive: true,
    nomeParrocchia: 'Parrocchia San Francesco d\'Assisi',
    diocesi: 'Diocesi di Roma',
    annoCatechisticoCorrente: '2026-2027',
    durataValiditaConsensoMesi: 12,
    sogliaAssenzeConsecutive: 3,
  );
  await LocalDatabase.parishConfig().put(ParishConfig.storageKey, parishConfig.toMap());
  
  // Create aulas (rooms)
  final aulas = <Aula>[];
  final aulaNames = ['Aula San Giuseppe', 'Aula Santa Chiara', 'Sala Parrocchiale', 'Cappella', 'Aula San Francesco', 'Aula Beata Vergine'];
  for (int i = 0; i < aulaNames.length; i++) {
    final aula = Aula(
      stanzaId: _generateId('stanza'),
      nomeStanza: aulaNames[i],
      capienzaMassima: 20 + _random.nextInt(15),
      noteAccessibilita: _random.nextBool() ? 'Accessibile sedie a rotelle' : '',
      lastModifiedBy: 'Responsabile',
    );
    aulas.add(aula);
    await LocalDatabase.aula().put(aula.stanzaId, aula.toMap());
  }
  
  // Generate 2 catechists per class (10 classes)
  final catechistIds = <String>[];
  final catechistNames = <String, String>{};
  for (int i = 0; i < numClasses * catechistsPerClass; i++) {
    final id = _generateId('catechist');
    final name = '${_randomName()} ${_randomSurname()}';
    catechistIds.add(id);
    catechistNames[id] = name;
  }
  
  // Responsabile
  final responsabileId = 'catechist_responsabile_001';
  catechistIds.add(responsabileId);
  catechistNames[responsabileId] = 'Don Marco Rossi (Responsabile)';
  
  // Create 10 classes
  final classes = <SchoolClass>[];
  final allStudents = <Student>[];
  final allPlanning = <PlanningMeeting>[];
  final allCatechesi = <Catechesi>[];
  
  for (int classIdx = 0; classIdx < numClasses; classIdx++) {
    final className = _classNames[classIdx % _classNames.length];
    final percorso = _percorsi[classIdx % _percorsi.length];
    final livello = (classIdx % 2) + 1;
    final uniqueCode = _generateUniqueCode();
    final classId = _generateId('class');
    
    // Assign 2 catechists to this class
    final classCatechistIds = catechistIds.sublist(classIdx * 2, classIdx * 2 + 2);
    final catechistRoles = <String, String>{};
    catechistRoles[classCatechistIds[0]] = 'TITOLARE';
    catechistRoles[classCatechistIds[1]] = 'AIUTO';
    
    // Add responsabile to all classes
    final allCatechistIds = [...classCatechistIds, responsabileId, AuthService.localUserId];
    catechistRoles[responsabileId] = 'RESPONSABILE';
    catechistRoles[AuthService.localUserId] = 'CATECHISTA';
    
    // Create room slots for this class
    final roomSlots = <RoomSlot>[];
    final giornoSettimana = 1 + (classIdx % 5); // Mon-Fri
    final aula = aulas[classIdx % aulas.length];
    roomSlots.add(RoomSlot(
      slotId: _generateId('slot'),
      stanzaId: aula.stanzaId,
      nomeStanza: aula.nomeStanza,
      giornoSettimana: giornoSettimana,
      oraInizio: '15:00',
      oraFine: '16:30',
      note: 'Incontro settimanale',
    ));
    
    final schoolClass = SchoolClass(
      id: classId,
      name: className,
      studentIds: [],
      catechistIds: allCatechistIds,
      lastModifiedBy: 'Responsabile',
      uniqueCode: uniqueCode,
      nameLocked: false,
      creatorId: responsabileId,
      creatorName: catechistNames[responsabileId]!,
      creatorCatechistId: responsabileId,
      associatedCatechistIds: classCatechistIds,
      catechistDeviceCounts: {for (final id in allCatechistIds) id: 1},
      percorso: percorso,
      livello: livello,
      annoCatechistico: '2026-2027',
      archived: false,
      catechistRoles: catechistRoles,
      roomSlots: roomSlots,
    );
    
    classes.add(schoolClass);
    await LocalDatabase.classes().put(classId, schoolClass.toMap());
    
    // Generate 15 students for this class
    for (int studentIdx = 0; studentIdx < studentsPerClass; studentIdx++) {
      final studentId = _generateId('student');
      final name = _randomName();
      final surname = _randomSurname();
      final birthDate = _randomBirthDate(2010, 2016); // Ages 10-16
      
      final motherName = _randomMotherName();
      final motherSurname = _randomSurname();
      final fatherName = _randomFatherName();
      final fatherSurname = _randomSurname();
      
      final student = Student(
        id: studentId,
        name: name,
        surname: surname,
        birthDate: birthDate,
        classId: classId,
        classUniqueCode: uniqueCode,
        motherName: motherName,
        motherSurname: motherSurname,
        fatherName: fatherName,
        fatherSurname: fatherSurname,
        motherPhone: _randomPhone(),
        fatherPhone: _randomPhone(),
        studentPhone: _random.nextBool() ? _randomPhone() : '',
        allergies: _randomAllergy(),
        autonomousExits: _randomAutonomousExit(),
        notes: _randomNote(),
        consensoPrivacyFirmato: true,
        dataFirmaConsenso: DateTime.now().subtract(Duration(days: _random.nextInt(365))),
        dataScadenzaTrattamento: DateTime.now().add(Duration(days: 365)),
        consensoUsciteAutonome: _random.nextBool(),
        contributoVersato: _random.nextBool(),
        contributoEuros: _random.nextBool() ? 20.0 + _random.nextDouble() * 80 : 0,
        annoContributo: '2026-2027',
        noteAllergieSalute: _random.nextBool() ? 'Nessuna allergia nota' : null,
        statoPercorso: 'ATTIVO',
        annoIscrizione: '2026-2027',
        lastModifiedBy: catechistNames[classCatechistIds[0]]!,
      );
      
      allStudents.add(student);
      await LocalDatabase.students().put(studentId, student.toMap());
      
      // Add student to class
      schoolClass.studentIds.add(studentId);
    }
    
    // Update class with student IDs
    await LocalDatabase.classes().put(classId, schoolClass.toMap());
    
    // Generate planning meetings for this class (about 20 meetings per year)
    for (int meetingIdx = 0; meetingIdx < 20; meetingIdx++) {
      final meetingId = _generateId('meeting');
      final baseDate = DateTime(2026, 9, 15); // Start mid-September
      final meetingDate = baseDate.add(Duration(days: meetingIdx * 14 + _random.nextInt(7))); // Bi-weekly
      
      final isReunion = meetingIdx % 10 == 0; // Every 10th is a reunion
      
      final planning = PlanningMeeting(
        id: meetingId,
        classId: classId,
        classUniqueCode: uniqueCode,
        createdBy: catechistNames[classCatechistIds[0]]!,
        date: meetingDate,
        time: isReunion ? '20:30' : null,
        title: isReunion 
            ? 'Riunione catechisti - ${meetingDate.day}/${meetingDate.month}'
            : 'Incontro: ${_catechesiTitles[meetingIdx % _catechesiTitles.length]}',
        activity: isReunion 
            ? 'Programmazione e condivisione'
            : 'Catechesi, gioco, preghiera, merenda',
        notes: '',
        isReunion: isReunion,
        lastModifiedBy: catechistNames[classCatechistIds[0]]!,
      );
      
      allPlanning.add(planning);
      await LocalDatabase.planning().put(meetingId, planning.toMap());
    }
  }
  
  // Generate catechesi (shared across all classes)
  for (int i = 0; i < _catechesiTitles.length; i++) {
    final catechesiId = _generateId('catechesi');
    final catechesi = Catechesi(
      id: catechesiId,
      classUniqueCode: null, // Global
      title: _catechesiTitles[i],
      tags: _catechesiTags[i],
      biblicalReferences: _biblicalRefs[i],
      websiteReferences: _websiteRefs[_random.nextInt(_websiteRefs.length)],
      photoIds: [],
      description: 'Descrizione approfondita per: ${_catechesiTitles[i]}. '
          'Questa scheda fornisce spunti per la catechesi, riferimenti biblici, '
          'e suggerimenti per attività con i ragazzi.',
      createdAt: DateTime.now().subtract(Duration(days: _random.nextInt(365))),
      updatedAt: DateTime.now(),
      lastModifiedBy: 'Don Marco Rossi (Responsabile)',
    );
    allCatechesi.add(catechesi);
    await LocalDatabase.catechesi().put(catechesiId, catechesi.toMap());
  }
  
  // Generate some contact notes
  for (final student in allStudents.take(50)) { // Notes for first 50 students
    final noteId = _generateId('contact');
    final mediums = ['de_visu', 'whatsapp', 'cellulare'];
    final note = ContactNote(
      id: noteId,
      studentId: student.id,
      classUniqueCode: student.classUniqueCode,
      dateTime: DateTime.now().subtract(Duration(days: _random.nextInt(90))),
      medium: mediums[_random.nextInt(mediums.length)],
      notes: 'Colloquio con i genitori su partecipazione e comportamento.',
      lastModifiedBy: catechistNames.values.elementAt(_random.nextInt(catechistNames.length)),
    );
    await LocalDatabase.contactNotes().put(noteId, note.toMap());
  }
  
  // Generate some daily notes
  for (final planning in allPlanning.take(30)) {
    if (planning.isReunion) continue;
    for (final student in allStudents.where((s) => s.classId == planning.classId).take(5)) {
      final noteId = _generateId('dailynote');
      final note = StudentDailyNote(
        id: noteId,
        studentId: student.id,
        meetingId: planning.id,
        classUniqueCode: planning.classUniqueCode,
        text: _randomNote(),
        createdAt: planning.date,
        updatedAt: planning.date,
        lastModifiedBy: catechistNames.values.elementAt(_random.nextInt(catechistNames.length)),
      );
      await LocalDatabase.studentDailyNotes().put(noteId, note.toMap());
    }
  }
  
  // Generate some audit logs
  final actions = AuditActionType.values;
  final entityTypes = ['RAGAZZO', 'CLASSE', 'CATECHISTA', 'CONSENSO'];
  for (int i = 0; i < 20; i++) {
    final logId = _generateId('audit');
    final log = AuditLog(
      logId: logId,
      timestamp: DateTime.now().subtract(Duration(days: _random.nextInt(30), hours: _random.nextInt(24))),
      actionType: actions[_random.nextInt(actions.length)],
      executedByCatechistId: catechistIds[_random.nextInt(catechistIds.length)],
      executedByCatechistName: catechistNames.values.elementAt(_random.nextInt(catechistNames.length)),
      affectedEntityType: entityTypes[_random.nextInt(entityTypes.length)],
      affectedEntityId: _generateId('entity'),
      signature: '', // Will be filled by the service
    );
    await LocalDatabase.auditLog().put(logId, log.toMap());
  }
  
  // Generate avvisi templates
  final templates = [
    AvvisoTemplate(
      id: _generateId('template'),
      title: 'Convocazione riunione catechisti',
      text: 'Gentili catechisti, vi ricordo la riunione di programmazione per il giorno {{data_incontro}} alle ore {{ora}} presso {{luogo}}. Ordine del giorno: {{argomenti}}.',
    ),
    AvvisoTemplate(
      id: _generateId('template'),
      title: 'Avviso ai genitori - Incontro catechismo',
      text: 'Gentili genitori, vi informiamo che l\'incontro di catechismo di {{nome_gruppo}} si terrà il giorno {{data_incontro}} alle ore {{ora}} in {{luogo}}. Tema: {{tema}}. Portare: {{materiale}}.',
    ),
    AvvisoTemplate(
      id: _generateId('template'),
      title: 'Comunicazione variazione orario',
      text: 'Si comunica che l\'incontro di {{nome_gruppo}} del giorno {{data_incontro}} è anticipato/posticipato alle ore {{nuovo_orario}}. Ci scusiamo per il disagio.',
    ),
  ];
  
  for (final template in templates) {
    await LocalDatabase.avvisi().put(template.id, template.toMap());
  }
  
  stdout.writeln('   ✓ Created ${classes.length} classes');
  stdout.writeln('   ✓ Created ${allStudents.length} students');
  stdout.writeln('   ✓ Created ${allPlanning.length} planning meetings');
  stdout.writeln('   ✓ Created ${allCatechesi.length} catechesi');
  stdout.writeln('   ✓ Created ${aulas.length} aulas');
  stdout.writeln('   ✓ Created ${catechistIds.length} catechists (including responsabile)');
}

Future<void> _generateSingleClass() async {
  // Clear existing data
  await LocalDatabase.classes().clear();
  await LocalDatabase.students().clear();
  await LocalDatabase.planning().clear();
  await LocalDatabase.attendance().clear();
  await LocalDatabase.documents().clear();
  await LocalDatabase.documentDeliveries().clear();
  await LocalDatabase.attachments().clear();
  await LocalDatabase.contactNotes().clear();
  await LocalDatabase.catechesi().clear();
  await LocalDatabase.meetingCatechesi().clear();
  await LocalDatabase.studentDailyNotes().clear();
  await LocalDatabase.aula().clear();
  await LocalDatabase.avvisi().clear();
  await LocalDatabase.auditLog().clear();
  await LocalDatabase.parishConfig().clear();
  
  // Create parish config (without responsabile mode)
  final parishConfig = ParishConfig(
    isResponsabileModeActive: false,
    nomeParrocchia: 'Parrocchia San Francesco d\'Assisi',
    diocesi: 'Diocesi di Roma',
    annoCatechisticoCorrente: '2026-2027',
    durataValiditaConsensoMesi: 12,
    sogliaAssenzeConsecutive: 3,
  );
  await LocalDatabase.parishConfig().put(ParishConfig.storageKey, parishConfig.toMap());
  
  // Create one aula
  final aula = Aula(
    stanzaId: _generateId('stanza'),
    nomeStanza: 'Aula San Giuseppe',
    capienzaMassima: 25,
    noteAccessibilita: 'Accessibile sedie a rotelle',
    lastModifiedBy: 'Catechista',
  );
  await LocalDatabase.aula().put(aula.stanzaId, aula.toMap());
  
  // Create 2 catechists for this class
  final catechist1Id = _generateId('catechist');
  final catechist1Name = '${_randomName()} ${_randomSurname()}';
  final catechist2Id = _generateId('catechist');
  
  final uniqueCode = _generateUniqueCode();
  final classId = _generateId('class');
  
  final classCatechistIds = [catechist1Id, catechist2Id, AuthService.localUserId];
  final catechistRoles = <String, String>{
    catechist1Id: 'TITOLARE',
    catechist2Id: 'AIUTO',
    AuthService.localUserId: 'CATECHISTA',
  };
  
  // Create room slot
  final roomSlots = <RoomSlot>[
    RoomSlot(
      slotId: _generateId('slot'),
      stanzaId: aula.stanzaId,
      nomeStanza: aula.nomeStanza,
      giornoSettimana: 3, // Wednesday
      oraInizio: '15:30',
      oraFine: '17:00',
      note: 'Incontro settimanale catechismo',
    ),
  ];
  
  final schoolClass = SchoolClass(
    id: classId,
    name: 'Prima Comunione 1° Anno',
    studentIds: [],
    catechistIds: classCatechistIds,
    lastModifiedBy: catechist1Name,
    uniqueCode: uniqueCode,
    nameLocked: false,
    creatorId: catechist1Id,
    creatorName: catechist1Name,
    creatorCatechistId: catechist1Id,
    associatedCatechistIds: [catechist2Id],
    catechistDeviceCounts: {catechist1Id: 1, catechist2Id: 1},
    percorso: 'Prima Comunione',
    livello: 1,
    annoCatechistico: '2026-2027',
    archived: false,
    catechistRoles: catechistRoles,
    roomSlots: roomSlots,
  );
  
  await LocalDatabase.classes().put(classId, schoolClass.toMap());
  
  // Generate 15 students
  final students = <Student>[];
  for (int i = 0; i < studentsPerClass; i++) {
    final studentId = _generateId('student');
    final name = _randomName();
    final surname = _randomSurname();
    final birthDate = _randomBirthDate(2014, 2015); // Ages 11-12 for Prima Comunione
    
    final student = Student(
      id: studentId,
      name: name,
      surname: surname,
      birthDate: birthDate,
      classId: classId,
      classUniqueCode: uniqueCode,
      motherName: _randomMotherName(),
      motherSurname: _randomSurname(),
      fatherName: _randomFatherName(),
      fatherSurname: _randomSurname(),
      motherPhone: _randomPhone(),
      fatherPhone: _randomPhone(),
      studentPhone: _random.nextBool() ? _randomPhone() : '',
      allergies: _randomAllergy(),
      autonomousExits: _randomAutonomousExit(),
      notes: _randomNote(),
      consensoPrivacyFirmato: true,
      dataFirmaConsenso: DateTime.now().subtract(Duration(days: _random.nextInt(180))),
      dataScadenzaTrattamento: DateTime.now().add(Duration(days: 365)),
      consensoUsciteAutonome: _random.nextBool(),
      contributoVersato: _random.nextBool(),
      contributoEuros: _random.nextBool() ? 20.0 + _random.nextDouble() * 50 : 0,
      annoContributo: '2026-2027',
      noteAllergieSalute: _random.nextBool() ? 'Nessuna allergia nota' : null,
      statoPercorso: 'ATTIVO',
      annoIscrizione: '2026-2027',
      lastModifiedBy: catechist1Name,
    );
    
    students.add(student);
    await LocalDatabase.students().put(studentId, student.toMap());
    schoolClass.studentIds.add(studentId);
  }
  
  // Update class with student IDs
  await LocalDatabase.classes().put(classId, schoolClass.toMap());
  
  // Generate planning meetings
  for (int i = 0; i < 15; i++) {
    final meetingId = _generateId('meeting');
    final baseDate = DateTime(2026, 10, 1);
    final meetingDate = baseDate.add(Duration(days: i * 14));
    
    final isReunion = i % 7 == 0;
    
    final planning = PlanningMeeting(
      id: meetingId,
      classId: classId,
      classUniqueCode: uniqueCode,
      createdBy: catechist1Name,
      date: meetingDate,
      time: isReunion ? '20:30' : null,
      title: isReunion 
          ? 'Riunione catechisti'
          : 'Incontro: ${_catechesiTitles[i % _catechesiTitles.length]}',
      activity: isReunion 
          ? 'Programmazione'
          : 'Catechesi, gioco, preghiera, merenda',
      notes: '',
      isReunion: isReunion,
      lastModifiedBy: catechist1Name,
    );
    
    await LocalDatabase.planning().put(meetingId, planning.toMap());
  }
  
  // Generate a few catechesi
  for (int i = 0; i < 5; i++) {
    final catechesiId = _generateId('catechesi');
    final catechesi = Catechesi(
      id: catechesiId,
      classUniqueCode: uniqueCode,
      title: _catechesiTitles[i],
      tags: _catechesiTags[i],
      biblicalReferences: _biblicalRefs[i],
      websiteReferences: _websiteRefs[_random.nextInt(_websiteRefs.length)],
      photoIds: [],
      description: 'Descrizione per: ${_catechesiTitles[i]}',
      createdAt: DateTime.now().subtract(Duration(days: _random.nextInt(180))),
      updatedAt: DateTime.now(),
      lastModifiedBy: catechist1Name,
    );
    await LocalDatabase.catechesi().put(catechesiId, catechesi.toMap());
  }
  
  // Contact notes for some students
  for (final student in students.take(5)) {
    final noteId = _generateId('contact');
    final note = ContactNote(
      id: noteId,
      studentId: student.id,
      classUniqueCode: uniqueCode,
      dateTime: DateTime.now().subtract(Duration(days: _random.nextInt(30))),
      medium: ['de_visu', 'whatsapp', 'cellulare'][_random.nextInt(3)],
      notes: 'Colloquio informativo con i genitori.',
      lastModifiedBy: catechist1Name,
    );
    await LocalDatabase.contactNotes().put(noteId, note.toMap());
  }
  
  stdout.writeln('   ✓ Created 1 class');
  stdout.writeln('   ✓ Created ${students.length} students');
  stdout.writeln('   ✓ Created 2 catechists');
}

Future<void> _writeCatechHubFile(String filename, String encryptedData) async {
  final directory = Directory.current;
  final file = File('${directory.path}${Platform.pathSeparator}$filename');
  await file.writeAsString(encryptedData);
  stdout.writeln('   📁 File written to: ${file.path}');
}