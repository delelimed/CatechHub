// ══════════════════════════════════════════════════════════════════════════════
// historical_record.dart — CatechHub (archivio storico e progresso dei ragazzi)
//
// Modulo "Archivio Storico e Progresso dei Ragazzi": rappresenta la
// fotografia IMMUTABILE di un ragazzo al termine di un anno catechistico.
// Viene generato dalla funzione "Concludi Anno Catechistico" (riservata al
// Responsabile) e conserva, per ogni studente, i dati aggregati dell'anno:
//   - Anno catechistico, classe e catechista di riferimento
//   - Sacramenti ricevuti (Battesimo, Prima Confessione, Comunione, Cresima)
//   - Percentuale di presenza
//   - Riepilogo delle valutazioni
//
// REGOLE DI IMMUTABILITÀ:
//   Il record è uno snapshot: una volta scritto nel box Hive non esiste un
//   flusso di update. Ogni nuovo passaggio d'anno produce un NUOVO record
//   con un nuovo [recordId]. L'unica cancellazione ammessa è quella legata
//   al Diritto all'Oblio / reset totale (cascade delete dello studente).
//
// VISIBILITÀ (ACL):
//   - Responsabile Catechistico: accesso pieno all'intero archivio.
//   - Catechista: vede SOLO i record degli studenti attualmente assegnati
//     alle proprie classi (storico degli anni precedenti). Se lo studente
//     lascia la classe, i dati locali "scadono" e spariscono dalla vista
//     (filtro applicato in HistoricalAccessPolicy).
//
// STORAGE:
//   Salvato nel box Hive "historical_records_box" con chiave = recordId.
// ══════════════════════════════════════════════════════════════════════════════

/// Sacramenti ricevuti da un ragazzo nel percorso catechistico.
enum Sacrament {
  battesimo('BATTESIMO', 'Battesimo'),
  primaConfessione('PRIMA_CONFESSIONE', 'Prima Confessione'),
  comunione('COMUNIONE', 'Prima Comunione'),
  cresima('CRESIMA', 'Cresima');

  const Sacrament(this.storageValue, this.label);

  /// Valore persistente (stringa di archivio).
  final String storageValue;

  /// Etichetta localizzata per le UI.
  final String label;

  static Sacrament fromStorageValue(String? value) {
    return Sacrament.values.firstWhere(
      (s) => s.storageValue == value,
      orElse: () => Sacrament.battesimo,
    );
  }

  /// Deserializza una lista persistente in [List<Sacrament>].
  /// Le voci non riconosciute vengono ignorate.
  static List<Sacrament> listFromStorage(Object? raw) {
    if (raw is! List) return const [];
    final values = raw.map((e) => e.toString()).toList();
    final out = <Sacrament>[];
    for (final v in values) {
      final sacrament = Sacrament.values.firstWhere(
        (s) => s.storageValue == v,
        orElse: () => Sacrament.battesimo,
      );
      // Evita di introdurre un falso "Battesimo" per valori sconosciuti.
      if (sacrament.storageValue != v) continue;
      if (!out.contains(sacrament)) out.add(sacrament);
    }
    return out;
  }
}

/// Record immutabile dell'archivio storico di un ragazzo.
class HistoricalRecord {
  /// ID univoco del record (formato: `hist_<microsecondsSinceEpoch>`).
  final String recordId;

  /// ID dello studente a cui si riferisce lo snapshot.
  final String studentId;

  /// Anno catechistico di riferimento (es. "2026-2027").
  final String academicYear;

  /// ID della classe di provenienza (tracciabilità, può essere vuoto).
  final String classId;

  /// Nome della classe al momento della chiusura dell'anno.
  final String className;

  /// ID del catechista titolare della classe nell'anno archiviato.
  final String catechistId;

  /// Sacramenti ricevuti fino alla fine dell'anno archiviato.
  final List<Sacrament> sacramentsReceived;

  /// Percentuale di presenza del ragazzo nell'anno (0–100).
  final double attendancePercentage;

  /// Riepilogo testuale delle valutazioni del ragazzo.
  final String evaluationsSummary;

  /// Timestamp di creazione dello snapshot (UTC, ISO 8601).
  final DateTime createdAt;

  HistoricalRecord({
    required this.recordId,
    required this.studentId,
    required this.academicYear,
    this.classId = '',
    required this.className,
    this.catechistId = '',
    this.sacramentsReceived = const [],
    this.attendancePercentage = 0,
    this.evaluationsSummary = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  HistoricalRecord copyWith({
    String? recordId,
    String? studentId,
    String? academicYear,
    String? classId,
    String? className,
    String? catechistId,
    List<Sacrament>? sacramentsReceived,
    double? attendancePercentage,
    String? evaluationsSummary,
    DateTime? createdAt,
  }) {
    return HistoricalRecord(
      recordId: recordId ?? this.recordId,
      studentId: studentId ?? this.studentId,
      academicYear: academicYear ?? this.academicYear,
      classId: classId ?? this.classId,
      className: className ?? this.className,
      catechistId: catechistId ?? this.catechistId,
      sacramentsReceived: sacramentsReceived ?? this.sacramentsReceived,
      attendancePercentage: attendancePercentage ?? this.attendancePercentage,
      evaluationsSummary: evaluationsSummary ?? this.evaluationsSummary,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Deserializza da Map (proveniente da Hive o da sync CRDT).
  factory HistoricalRecord.fromMap(String id, Map<String, dynamic> data) {
    return HistoricalRecord(
      recordId: id,
      studentId: data['studentId'] ?? '',
      academicYear: data['academicYear'] ?? '',
      classId: data['classId'] ?? '',
      className: data['className'] ?? '',
      catechistId: data['catechistId'] ?? '',
      sacramentsReceived: Sacrament.listFromStorage(data['sacramentsReceived']),
      attendancePercentage:
          (data['attendancePercentage'] as num?)?.toDouble() ?? 0,
      evaluationsSummary: data['evaluationsSummary'] ?? '',
      createdAt: DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  /// Serializza in Map per salvataggio in Hive o trasmissione sync.
  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'academicYear': academicYear,
      'classId': classId,
      'className': className,
      'catechistId': catechistId,
      'sacramentsReceived': sacramentsReceived
          .map((s) => s.storageValue)
          .toList(),
      'attendancePercentage': attendancePercentage,
      'evaluationsSummary': evaluationsSummary,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
