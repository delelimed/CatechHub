/// Logica pura del "conteggio rapido" in CateREG.
///
/// Confronta il numero di ragazzi rilevati fisicamente dal catechista con i
/// presenti dell'appello odierno, senza scrivere alcun dato su Hive:
/// - [recordsOnDate] filtra i record di presenza per giorno.
/// - [recordsOfClasses] filtra i record per le classi selezionate.
/// - [presentCount]/[totalPresentCount] contano i "Presente".
/// - [presentStudentIds] estrae gli id degli studenti presenti.
/// - [isComplete] verifica se il conteggio coincide con i presenti.
///
/// Il formato di ogni record è quello della box Hive `attendance`:
///   { 'date': ISO8601, 'classId': String, 'presence': {studentId: stato} }
/// con stato in 'Presente' | 'Assente'.
class QuickCountLogic {
  QuickCountLogic._();

  /// True se le due date cadono nello stesso giorno (indipendente dall'ora).
  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Record di presenza che cadono nel giorno [date].
  static List<Map<String, dynamic>> recordsOnDate(
    List<Map<String, dynamic>> records,
    DateTime date,
  ) {
    return records.where((r) {
      final d = DateTime.tryParse(r['date']?.toString() ?? '');
      return d != null && isSameDay(d, date);
    }).toList();
  }

  /// Record di presenza appartenenti a una delle classi in [classIds].
  static List<Map<String, dynamic>> recordsOfClasses(
    List<Map<String, dynamic>> records,
    Set<String> classIds,
  ) {
    return records
        .where((r) => classIds.contains(r['classId']?.toString()))
        .toList();
  }

  /// Numero di ragazzi marcati "Presente" in un singolo record di appello.
  static int presentCount(Map<String, dynamic> record) {
    final presence = Map<String, dynamic>.from(
      record['presence'] as Map? ?? {},
    );
    return presence.values.where((v) => v?.toString() == 'Presente').length;
  }

  /// Totale dei presenti sull'insieme di record (somma di [presentCount]).
  static int totalPresentCount(List<Map<String, dynamic>> records) {
    return records.fold(0, (sum, r) => sum + presentCount(r));
  }

  /// Insieme degli id degli studenti marcati "Presente" nei record forniti.
  static Set<String> presentStudentIds(List<Map<String, dynamic>> records) {
    final ids = <String>{};
    for (final r in records) {
      final presence = Map<String, dynamic>.from(r['presence'] as Map? ?? {});
      for (final entry in presence.entries) {
        if (entry.value?.toString() == 'Presente') {
          ids.add(entry.key.toString());
        }
      }
    }
    return ids;
  }

  /// True se il numero rilevato coincide con i presenti dell'appello.
  static bool isComplete(int detected, int expected) {
    return detected == expected;
  }
}
