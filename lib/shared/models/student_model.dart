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

import 'historical_record.dart';

class Student {
  /// ID univoco (formato: `local_<microsecondsSinceEpoch>`).
  final String id;

  /// Nome del ragazzo (normalizzato in Title Case dal repository).
  final String name;

  /// Cognome del ragazzo (normalizzato in Title Case dal repository).
  final String surname;

  /// FK verso SchoolClass (null se non ancora assegnato a un gruppo).
  final String? classId;

  /// Codice univoco di 40 cifre della classe di appartenenza.
  /// Copia ridondante di SchoolClass.uniqueCode per identificare la classe
  /// anche in assenza di relazione diretta (utile per sync multi-classe).
  final String? classUniqueCode;

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

  /// Email del genitore/tutore (facoltativa, importata da Excel/CSV).
  final String parentEmail;

  // ─── Dati sanitari e note ───────────────────────────────────────────
  /// Allergie alimentari o farmacologiche (testo libero). Dato critico
  /// per la sicurezza durante incontri con pasti/merende.
  final String? allergies;

  /// Autorizzazione per uscite autonome senza accompagnamento.
  final String? autonomousExits;

  /// Note libere del catechista sullo studente.
  final String? notes;

  // ─── Campi GDPR / privacy (modulo di iscrizione unificato) ─────────────

  /// True se il modulo di iscrizione della famiglia è stato firmato
  /// (equivalente permesso privacy) per il trattamento dei dati.
  final bool consensoPrivacyFirmato;

  /// Data di firma del modulo di iscrizione (data_firma_consenso).
  final DateTime? dataFirmaConsenso;

  /// Scadenza del trattamento dei dati, calcolata automaticamente
  /// (data_firma_consenso + durata validità configurata in ParishConfig).
  final DateTime? dataScadenzaTrattamento;

  /// Consenso esplicito alle uscite autonome senza accompagnamento.
  final bool consensoUsciteAutonome;

  /// Contributo volontario versato in occasione dell'iscrizione.
  final bool contributoVersato;

  /// Importo (in euro, facoltativo) del contributo volontario.
  final double contributoEuros;

  /// Anno catechistico a cui si riferisce il contributo (es. "2026-2027").
  final String annoContributo;

  /// Note allergie/salute sensibili, cifrate a livello di campo via
  /// [FieldEncryptionService] prima della persistenza.
  final String? noteAllergieSalute;

  // ─── Campi della modalità "Responsabile Catechistico" ──────────────────

  /// Stato del percorso catechistico:
  ///   "ATTIVO" | "FERMO" | "RITIRATO"
  final String statoPercorso;

  /// Anno catechistico di iscrizione (es. "2026-2027").
  final String annoIscrizione;

  // ─── Campi dell'archivio storico / progresso ─────────────────────────────

  /// Sacramenti ricevuti dal ragazzo (Battesimo, Prima Confessione,
  /// Comunione, Cresima). Aggiornati dal catechista/responsabile e
  /// "fotografati" in ogni [HistoricalRecord] alla chiusura dell'anno.
  final List<Sacrament> sacraments;

  /// Nome del catechista che ha modificato per ultimo questo record.
  final String lastModifiedBy;

  /// Timestamp di creazione (UTC, ISO 8601).
  final DateTime createdAt;

  /// Timestamp dell'ultima modifica (UTC, ISO 8601).
  final DateTime updatedAt;

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
    this.parentEmail = '',
    this.classId,
    this.classUniqueCode,
    this.allergies,
    this.autonomousExits,
    this.notes,
    this.consensoPrivacyFirmato = false,
    this.dataFirmaConsenso,
    this.dataScadenzaTrattamento,
    this.consensoUsciteAutonome = false,
    this.contributoVersato = false,
    this.contributoEuros = 0,
    this.annoContributo = '',
    this.noteAllergieSalute,
    this.statoPercorso = 'ATTIVO',
    this.annoIscrizione = '',
    this.sacraments = const [],
    this.lastModifiedBy = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// Deserializza da Map (proveniente da Hive o da sync CRDT).
  /// I campi mancanti defaultano a stringa vuota o DateTime.now().
  factory Student.fromMap(String id, Map<String, dynamic> data) {
    return Student(
      id: id,
      name: data['name'] ?? '',
      surname: data['surname'] ?? '',
      birthDate:
          DateTime.tryParse(data['birthDate']?.toString() ?? '') ??
          DateTime.now(),
      classId: data['classId'],
      classUniqueCode: data['classUniqueCode'],
      motherName: data['motherName'] ?? '',
      motherSurname: data['motherSurname'] ?? '',
      fatherName: data['fatherName'] ?? '',
      fatherSurname: data['fatherSurname'] ?? '',
      motherPhone: data['motherPhone'] ?? '',
      fatherPhone: data['fatherPhone'] ?? '',
      studentPhone: data['studentPhone'] ?? '',
      parentEmail: data['parentEmail'] ?? '',
      allergies: data['allergies'],
      autonomousExits: data['autonomousExits'],
      notes: data['notes'],
      consensoPrivacyFirmato: data['consensoPrivacyFirmato'] ?? false,
      dataFirmaConsenso: DateTime.tryParse(
        data['dataFirmaConsenso']?.toString() ?? '',
      ),
      dataScadenzaTrattamento: DateTime.tryParse(
        data['dataScadenzaTrattamento']?.toString() ?? '',
      ),
      consensoUsciteAutonome: data['consensoUsciteAutonome'] ?? false,
      contributoVersato: data['contributoVersato'] ?? false,
      contributoEuros: (data['contributoEuros'] as num?)?.toDouble() ?? 0,
      annoContributo: data['annoContributo'] ?? '',
      noteAllergieSalute: data['noteAllergieSalute'],
      statoPercorso: data['statoPercorso'] ?? 'ATTIVO',
      annoIscrizione: data['annoIscrizione'] ?? '',
      sacraments: Sacrament.listFromStorage(data['sacraments']),
      lastModifiedBy: data['lastModifiedBy'] ?? '',
      createdAt:
          DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(data['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  /// Confronto A→Z case-insensitive per cognome, poi nome.
  /// Usato per ordinare la lista studenti in tutta l'app (dashboard,
  /// anagrafica, presenze, ecc.).
  static int compareBySurname(Student a, Student b) {
    final bySurname = a.surname.toLowerCase().compareTo(
      b.surname.toLowerCase(),
    );
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
    String? classUniqueCode,
    DateTime? birthDate,
    String? motherName,
    String? motherSurname,
    String? fatherName,
    String? fatherSurname,
    String? motherPhone,
    String? fatherPhone,
    String? studentPhone,
    String? parentEmail,
    String? allergies,
    String? autonomousExits,
    String? notes,
    bool? consensoPrivacyFirmato,
    DateTime? dataFirmaConsenso,
    DateTime? dataScadenzaTrattamento,
    bool? consensoUsciteAutonome,
    bool? contributoVersato,
    double? contributoEuros,
    String? annoContributo,
    String? noteAllergieSalute,
    String? statoPercorso,
    String? annoIscrizione,
    List<Sacrament>? sacraments,
    String? lastModifiedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Student(
      id: id ?? this.id,
      name: name ?? this.name,
      surname: surname ?? this.surname,
      birthDate: birthDate ?? this.birthDate,
      classId: classId ?? this.classId,
      classUniqueCode: classUniqueCode ?? this.classUniqueCode,
      motherName: motherName ?? this.motherName,
      motherSurname: motherSurname ?? this.motherSurname,
      fatherName: fatherName ?? this.fatherName,
      fatherSurname: fatherSurname ?? this.fatherSurname,
      motherPhone: motherPhone ?? this.motherPhone,
      fatherPhone: fatherPhone ?? this.fatherPhone,
      studentPhone: studentPhone ?? this.studentPhone,
      parentEmail: parentEmail ?? this.parentEmail,
      allergies: allergies ?? this.allergies,
      autonomousExits: autonomousExits ?? this.autonomousExits,
      notes: notes ?? this.notes,
      consensoPrivacyFirmato:
          consensoPrivacyFirmato ?? this.consensoPrivacyFirmato,
      dataFirmaConsenso: dataFirmaConsenso ?? this.dataFirmaConsenso,
      dataScadenzaTrattamento:
          dataScadenzaTrattamento ?? this.dataScadenzaTrattamento,
      consensoUsciteAutonome:
          consensoUsciteAutonome ?? this.consensoUsciteAutonome,
      contributoVersato: contributoVersato ?? this.contributoVersato,
      contributoEuros: contributoEuros ?? this.contributoEuros,
      annoContributo: annoContributo ?? this.annoContributo,
      noteAllergieSalute: noteAllergieSalute ?? this.noteAllergieSalute,
      statoPercorso: statoPercorso ?? this.statoPercorso,
      annoIscrizione: annoIscrizione ?? this.annoIscrizione,
      sacraments: sacraments ?? this.sacraments,
      lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
      'classUniqueCode': classUniqueCode,
      'motherName': motherName,
      'motherSurname': motherSurname,
      'fatherName': fatherName,
      'fatherSurname': fatherSurname,
      'motherPhone': motherPhone,
      'fatherPhone': fatherPhone,
      'studentPhone': studentPhone,
      'parentEmail': parentEmail,
      'allergies': allergies,
      'autonomousExits': autonomousExits,
      'notes': notes,
      'consensoPrivacyFirmato': consensoPrivacyFirmato,
      'dataFirmaConsenso': dataFirmaConsenso?.toIso8601String(),
      'dataScadenzaTrattamento': dataScadenzaTrattamento?.toIso8601String(),
      'consensoUsciteAutonome': consensoUsciteAutonome,
      'contributoVersato': contributoVersato,
      'contributoEuros': contributoEuros,
      'annoContributo': annoContributo,
      'noteAllergieSalute': noteAllergieSalute,
      'statoPercorso': statoPercorso,
      'annoIscrizione': annoIscrizione,
      'sacraments': sacraments.map((s) => s.storageValue).toList(),
      'lastModifiedBy': lastModifiedBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
