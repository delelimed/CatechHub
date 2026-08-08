// ══════════════════════════════════════════════════════════════════════════════
// slot_conflict_service.dart — CatechHub (rilevamento conflitti aule/orari)
//
// Modulo "Responsabile Catechistico — Logistica Parrocchiale":
// algoritmo locale per rilevare conflitti nell'assegnazione di aule e slot
// orari settimanali alle classi.
//
// REGOLE:
//  - Due slot CONFLIGGONO se: stessa aula, stesso giorno, orari sovrapposti.
//  - Una classe non può avere due slot sovrapposti tra loro (a prescindere
//    dall'aula), perché i catechisti non possono essere in due luoghi.
//  - La capienza: un aula non può ospitare una classe con più ragazzi della
//    capienza massima (warning, non blocco).
// ══════════════════════════════════════════════════════════════════════════════

import '../../shared/models/aula.dart';
import '../../shared/models/class_model.dart';

/// Eccezione sollevata quando l'assegnazione di uno slot genera un conflitto
/// con un'altra classe (bloccante).
class SlotConflictException implements Exception {
  final List<SlotConflict> conflicts;

  const SlotConflictException(this.conflicts);

  @override
  String toString() =>
      conflicts.map((c) => c.message).join('\n');
}

/// Esito di una verifica di conflitto.
class SlotConflict {
  /// Classe coinvolta nel conflitto.
  final SchoolClass classA;

  /// Seconda classe coinvolta (null se il conflitto è interno alla stessa).
  final SchoolClass? classB;

  /// Slot che collide.
  final RoomSlot slotA;

  /// Slot collidente (null se conflitto interno).
  final RoomSlot? slotB;

  /// Messaggio leggibile del conflitto.
  final String message;

  const SlotConflict({
    required this.classA,
    required this.classB,
    required this.slotA,
    required this.slotB,
    required this.message,
  });
}

/// Servizio stateless di rilevamento conflitti per la logistica parrocchiale.
class SlotConflictService {
  const SlotConflictService._();

  /// Verifica se l'inserimento di [newSlot] nella classe [target] genera
  /// conflitti con [allClasses] e [aulas]. Ritorna i conflitti trovati.
  static List<SlotConflict> findConflicts({
    required SchoolClass target,
    required RoomSlot newSlot,
    required List<SchoolClass> allClasses,
    required List<Aula> aulas,
  }) {
    final conflicts = <SlotConflict>[];
    final aula = aulas.where((a) => a.stanzaId == newSlot.stanzaId).firstOrNull;

    // Conflitto interno: la classe ha già uno slot nello stesso orario.
    for (final slot in target.roomSlots) {
      if (slot.slotId == newSlot.slotId) continue;
      if (slot.overlaps(newSlot)) {
        conflicts.add(SlotConflict(
          classA: target,
          classB: null,
          slotA: slot,
          slotB: newSlot,
          message: 'Conflitto interno: "${target.name}" ha già un impegno '
              'programmato nello stesso orario.',
        ));
      }
    }

    // Conflitto tra classi: stessa aula, stesso giorno, orari sovrapposti.
    for (final other in allClasses) {
      if (other.id == target.id) continue;
      for (final slot in other.roomSlots) {
        if (slot.stanzaId != newSlot.stanzaId) continue;
        if (slot.overlaps(newSlot)) {
          final aulaLabel = aula?.nomeStanza ?? newSlot.nomeStanza;
          conflicts.add(SlotConflict(
            classA: other,
            classB: target,
            slotA: slot,
            slotB: newSlot,
            message: "L'aula $aulaLabel è già occupata dalla classe "
                '"${other.name}" di ${_giorno(newSlot.giornoSettimana)} alle '
                '${newSlot.oraInizio}.',
          ));
        }
      }
    }

    // Warning di capienza: classe più numerosa della capienza dell'aula.
    if (aula != null && aula.capienzaMassima > 0 &&
        target.studentIds.length > aula.capienzaMassima) {
      conflicts.add(SlotConflict(
        classA: target,
        classB: null,
        slotA: newSlot,
        slotB: null,
        message: 'Attenzione: "${target.name}" ha ${target.studentIds.length} '
            'ragazzi, ma l\'aula "${aula.nomeStanza}" ha capienza massima di '
            '${aula.capienzaMassima}.',
      ));
    }

    return conflicts;
  }

  /// Verifica globale di tutti gli slot di tutte le classi (per la dashboard
  /// logistica). Ritorna tutti i conflitti rilevati.
  static List<SlotConflict> findAllConflicts(
    List<SchoolClass> allClasses,
    List<Aula> aulas,
  ) {
    final conflicts = <SlotConflict>[];
    for (final c in allClasses) {
      for (final slot in c.roomSlots) {
        final otherClasses = allClasses;
        for (final conflict in findConflicts(
          target: c,
          newSlot: slot,
          allClasses: otherClasses,
          aulas: aulas,
        )) {
          // Dedup: la verifica incrociata produrrebbe coppie duplicate.
          final already = conflicts.any((x) =>
              x.message == conflict.message &&
              x.slotA.slotId == conflict.slotA.slotId &&
              x.slotB?.slotId == conflict.slotB?.slotId);
          if (!already) conflicts.add(conflict);
        }
      }
    }
    return conflicts;
  }

  static String _giorno(int g) {
    const giorni = ['', 'Lunedì', 'Martedì', 'Mercoledì', 'Giovedì', 'Venerdì', 'Sabato', 'Domenica'];
    return g >= 1 && g <= 7 ? giorni[g] : 'giorno';
  }
}
