// ══════════════════════════════════════════════════════════════════════════════
// student_model.dart — CatechHub (modello anagrafica studente)
//
// Entità centrale del dominio. Rappresenta un ragazzo iscritto al
// catechismo con tutti i dati anagrafici e contatti dei genitori.
//
// CONTESTO PROGETTO:
//   Lo studente è l'entità pivot dell'intero sistema. Tutte le funzionalità
//   dell'app ruotano attorno ad essa:
//   - Presenze: ogni record di attendance_box referenzia studentId
//   - Documenti: ciclo vita (consegna/riconsegna) per studente
//   - Note di contatto: comunicazioni con i genitori per studente
//   - Note giornaliere: annotazioni individuali per studente+meeting
//   - Allegati: foto/documenti associati per studente
//   - Sync P2P: tutto il box students_box viene sincronizzato via CRDT
//
// STORAGE:
//   Salvato in Hive box "students_box" con chiave = student.id.
//   I nomi vengono normalizzati PRIMA del salvataggio tramite
//   NameFormatting.capitalizeWords() in StudentsRepository._normalize().
//
// RELAZIONI:
//   - SchoolClass (1) ──< (N) Student  [via classId]
//   - ContactNote (N) ──> (1) Student  [via studentId]
//   - StudentDailyNote (N) ──> (1) Student  [via studentId]
//   - Attachment (N) ──> (1) Student  [via parentId + parentType='student']
//
// SORT: sortedBySurname() ordina A→Z per cognome, poi nome (case-insensitive)
// ══════════════════════════════════════════════════════════════════════════════

class Student {
  /// ID univoco (formato: "local_<microsecondsSinceEpoch>").
  final String id;

  /// Nome del ragazzo (normalizzato in Title Case dal repository).
  final String name;

  /// Cognome del ragazzo (normalizzato in Title Case dal repository).
  final String surname;

  /// FK verso SchoolClass (null se non ancora assegnato a un gruppo).
  final String? classId;

  /// Data di nascita (formato ISO 8601).
  final DateTime birthDate;

  // ─── Genitori: Madre ────────────────────────────────────────────────
  final String motherName;
  final String motherSurname;
  final String motherPhone;

  // ─── Genitori: Padre ────────────────────────────────────────────────
  final String fatherName;
  final String fatherSurname;
  final String fatherPhone;

  /// Recapito telefonico diretto del ragazzo (se disponibile).
  final String studentPhone;

  // ─── Dati sanitari e note ───────────────────────────────────────────
  /// Allergie alimentari o farmacologiche (testo libero). Dato critico
  /// per la sicurezza durante incontri con pasti/merende.
  final String? allergies;

  /// Autorizzazione per uscite autonome senza accompagnamento.
  final String? autonomousExits;

  /// Note libere del catechista sullo studente.
  final String? notes;

  /// Nome del catechista che ha modificato per ultimo questo record.
  final String lastModifiedBy;

  Student({
    required this.id,
    required this.name,
    required this.surname,
    required this.birthDate,
    required this.motherName,
    required this.motherSurname,
    required this.fatherName,
    required this.fatherSurname,
    required this.motherPhone,
    required this.fatherPhone,
    required this.studentPhone,
    this.classId,
    this.allergies,
    this.autonomousExits,
    this.notes,
    this.lastModifiedBy = '',
  });

  /// Deserializza da Map (proveniente da Hive o da sync CRDT).
  /// I campi mancanti defaultano a stringa vuota o DateTime.now().
  factory Student.fromMap(String id, Map<String, dynamic> data) {
    return Student(
      id: id,
      name: data['name'] ?? '',
      surname: data['surname'] ?? '',
      birthDate: DateTime.tryParse(data['birthDate']?.toString() ?? '') ??
          DateTime.now(),
      classId: data['classId'],
      motherName: data['motherName'] ?? '',
      motherSurname: data['motherSurname'] ?? '',
      fatherName: data['fatherName'] ?? '',
      fatherSurname: data['fatherSurname'] ?? '',
      motherPhone: data['motherPhone'] ?? '',
      fatherPhone: data['fatherPhone'] ?? '',
      studentPhone: data['studentPhone'] ?? '',
      allergies: data['allergies'],
      autonomousExits: data['autonomousExits'],
      notes: data['notes'],
      lastModifiedBy: data['lastModifiedBy'] ?? '',
    );
  }

  /// Confronto A→Z case-insensitive per cognome, poi nome.
  /// Usato per ordinare la lista studenti in tutta l'app (dashboard,
  /// anagrafica, presenze, ecc.).
  static int compareBySurname(Student a, Student b) {
    final bySurname = a.surname.toLowerCase().compareTo(b.surname.toLowerCase());
    if (bySurname != 0) return bySurname;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  /// Restituisce una copia ordinata della lista per cognome+nome.
  static List<Student> sortedBySurname(Iterable<Student> students) {
    return students.toList()..sort(compareBySurname);
  }

  /// Pattern copyWith per aggiornamento immutabile dei campi.
  /// Usato in StudentsRepository._normalize() per applicare
  /// NameFormatting.capitalizeWords prima del salvataggio.
  Student copyWith({
    String? id,
    String? name,
    String? surname,
    String? classId,
    DateTime? birthDate,
    String? motherName,
    String? motherSurname,
    String? fatherName,
    String? fatherSurname,
    String? motherPhone,
    String? fatherPhone,
    String? studentPhone,
    String? allergies,
    String? autonomousExits,
    String? notes,
    String? lastModifiedBy,
  }) {
    return Student(
      id: id ?? this.id,
      name: name ?? this.name,
      surname: surname ?? this.surname,
      birthDate: birthDate ?? this.birthDate,
      classId: classId ?? this.classId,
      motherName: motherName ?? this.motherName,
      motherSurname: motherSurname ?? this.motherSurname,
      fatherName: fatherName ?? this.fatherName,
      fatherSurname: fatherSurname ?? this.fatherSurname,
      motherPhone: motherPhone ?? this.motherPhone,
      fatherPhone: fatherPhone ?? this.fatherPhone,
      studentPhone: studentPhone ?? this.studentPhone,
      allergies: allergies ?? this.allergies,
      autonomousExits: autonomousExits ?? this.autonomousExits,
      notes: notes ?? this.notes,
      lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
    );
  }

  /// Serializza in Map per salvataggio in Hive o trasmissione sync.
  /// birthDate viene serializzato in ISO 8601.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'surname': surname,
      'birthDate': birthDate.toIso8601String(),
      'classId': classId,
      'motherName': motherName,
      'motherSurname': motherSurname,
      'fatherName': fatherName,
      'fatherSurname': fatherSurname,
      'motherPhone': motherPhone,
      'fatherPhone': fatherPhone,
      'studentPhone': studentPhone,
      'allergies': allergies,
      'autonomousExits': autonomousExits,
      'notes': notes,
      'lastModifiedBy': lastModifiedBy,
    };
  }
}
