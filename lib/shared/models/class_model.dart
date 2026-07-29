// ══════════════════════════════════════════════════════════════════════════════
// class_model.dart — CatechHub (modello gruppo / classe catechistica)
//
// Rappresenta un gruppo di catechismo (es. "Prima elementare", "Gruppo
// Cresima 2026"). Mantiene relazioni many-to-many sia con gli studenti
// che con i catechisti tramite liste di ID.
//
// CONTESTO PROGETTO:
//   Il gruppo è l'unità organizzativa dell'app. Ogni catechista può
//   essere assegnato a uno o più gruppi (catechistIds), e ogni studente
//   appartiene a un gruppo (tramite classId in Student).
//
//   La dashboard mostra i dati del primo gruppo assegnato al catechista
//   corrente (authService.localUserId). PlanningMeeting e Attendance
//   referenziano la classe per le programmazioni e le presenze.
//
// RELAZIONI:
//   SchoolClass (1) ──< (N) Student          [via Student.classId]
//   SchoolClass (1) ──< (N) PlanningMeeting  [via classId]
//   SchoolClass (1) ──< (N) Attendance       [via classId]
//
// STORAGE:
//   Salvato in Hive box "classes_box" con chiave = class.id.
//   Sincronizzato via CRDT durante il sync P2P Bluetooth.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:math';

/// Genera un codice univoco di 40 cifre decimali (invisibile all'utente).
/// Usato per identificare una classe in modo probabilisticamente unico
/// a livello globale, senza necessità di un server centrale.
String generateClassUniqueCode() {
  final random = Random.secure();
  return List.generate(40, (_) => random.nextInt(10).toString()).join();
}

class SchoolClass {
  /// ID univoco (formato: "class_<microsecondsSinceEpoch>").
  final String id;

  /// Nome del gruppo (es. "Prima elementare", "Cresima 2026").
  final String name;

  /// Lista di Student.id assegnati a questo gruppo (FK many-to-many).
  final List<String> studentIds;

  /// Lista di ID catechisti assegnati a questo gruppo.
  /// Usato per filtrare i gruppi visibili nella dashboard:
  ///   classes.where((c) => c.catechistIds.contains(AuthService.localUserId))
  final List<String> catechistIds;

  /// Nome del catechista che ha modificato per ultimo questo record.
  final String lastModifiedBy;

  /// ID del catechista che ha creato la classe.
  /// Vuoto se la classe non ha un creatore (es. classi importate da backup).
  final String creatorId;

  /// Nome del catechista che ha creato la classe (al momento della creazione).
  /// Vuoto se la classe non ha un creatore.
  /// Usato come fallback per la verifica del creatore quando [creatorId] non
  /// corrisponde (confronto case‑insensitive e space‑insensitive).
  final String creatorName;

  /// Codice univoco di 40 cifre (invisibile all'utente).
  /// Identifica probabilisticamente la classe in tutto il mondo.
  final String uniqueCode;

  /// Se true, il nome della classe non può essere modificato da questo dispositivo.
  /// Impostato a true per classi ricevute via sync (l'utente si è unito).
  final bool nameLocked;

  /// Timestamp di creazione (UTC, ISO 8601).
  final DateTime createdAt;

  /// Timestamp dell'ultima modifica (UTC, ISO 8601).
  final DateTime updatedAt;

  SchoolClass({
    required this.id,
    required this.name,
    required this.studentIds,
    required this.catechistIds,
    this.lastModifiedBy = '',
    this.uniqueCode = '',
    this.nameLocked = false,
    this.creatorId = '',
    this.creatorName = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  SchoolClass copyWith({
    String? id,
    String? name,
    List<String>? studentIds,
    List<String>? catechistIds,
    String? lastModifiedBy,
    String? uniqueCode,
    bool? nameLocked,
    String? creatorId,
    String? creatorName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SchoolClass(
      id: id ?? this.id,
      name: name ?? this.name,
      studentIds: studentIds ?? this.studentIds,
      catechistIds: catechistIds ?? this.catechistIds,
      lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
      uniqueCode: uniqueCode ?? this.uniqueCode,
      nameLocked: nameLocked ?? this.nameLocked,
      creatorId: creatorId ?? this.creatorId,
      creatorName: creatorName ?? this.creatorName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory SchoolClass.fromMap(String id, Map<String, dynamic> data) {
    final raw = data['uniqueCode'] as String?;
    return SchoolClass(
      id: id,
      name: data['name'] ?? '',
      studentIds: (data['studentIds'] as List? ?? [])
          .map((value) => value.toString())
          .toList(),
      catechistIds: (data['catechistIds'] as List? ?? [])
          .map((value) => value.toString())
          .toList(),
      lastModifiedBy: data['lastModifiedBy'] ?? '',
      uniqueCode: (raw != null && raw.isNotEmpty) ? raw : '',
      nameLocked: data['nameLocked'] == true,
      creatorId: data['creatorId'] ?? '',
      creatorName: data['creatorName'] ?? '',
      createdAt: DateTime.tryParse(data['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(data['updatedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  /// Verifica se l'utente identificato da [userId] e [userName] è il creatore
  /// di questa classe.
  ///
  /// La verifica viene fatta sia tramite [creatorId] (confronto esatto) sia
  /// tramite [creatorName] (confronto case‑insensitive e space‑insensitive).
  /// Se almeno uno dei due corrisponde, l'utente è considerato il creatore.
  ///
  /// Le classi senza creatore ([creatorId] e [creatorName] entrambi vuoti)
  /// sono modificabili da chiunque (ritorna `true`).
  bool isCreator(String userId, String userName) {
    final hasCreator = creatorId.isNotEmpty || creatorName.isNotEmpty;
    if (!hasCreator) return true;
    if (creatorId == userId) return true;
    return _normalize(creatorName) == _normalize(userName);
  }

  static String _normalize(String s) =>
      s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'studentIds': studentIds,
      'catechistIds': catechistIds,
      'lastModifiedBy': lastModifiedBy,
      'uniqueCode': uniqueCode,
      'nameLocked': nameLocked,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
