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
      createdAt: DateTime.tryParse(data['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(data['updatedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'studentIds': studentIds,
      'catechistIds': catechistIds,
      'lastModifiedBy': lastModifiedBy,
      'uniqueCode': uniqueCode,
      'nameLocked': nameLocked,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
