/// Provider Riverpod del modulo "Supplenze Temporanee e Delega Sicura".
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_service.dart';
import '../../core/providers/current_class_provider.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/substitute_delegation.dart';
import '../classes/classes_provider.dart';
import 'substitute_delegation_repository.dart';
import 'substitute_delegation_service.dart';

final substituteDelegationRepoProvider =
    Provider<SubstituteDelegationRepository>((ref) {
      return SubstituteDelegationRepository();
    });

final substituteDelegationServiceProvider =
    Provider<SubstituteDelegationService>((ref) {
      return SubstituteDelegationService();
    });

final substituteDelegationsProvider =
    StreamProvider<List<SubstituteDelegation>>(
      (ref) => ref.watch(substituteDelegationRepoProvider).watchDelegations(),
    );

/// Deleghe in cui il catechista locale è il Supplente e che sono ancora
/// "visibili": attive o scadute ma non ancora acquisite dal Titolare (in
/// quest'ultimo stato la classe resta presente per permettere la consegna
/// dati, ma è di sola lettura).
final mySubstitutionsProvider = Provider<List<SubstituteDelegation>>((ref) {
  final catechistId = AuthService.getCatechistId();
  final delegations = ref
      .watch(substituteDelegationsProvider)
      .maybeWhen(data: (list) => list, orElse: () => <SubstituteDelegation>[]);
  final now = DateTime.now().toUtc();
  return delegations
      .where(
        (d) =>
            d.substituteCatechistId == catechistId &&
            d.status != SubstituteDelegationStatus.revoked &&
            d.status != SubstituteDelegationStatus.completed &&
            (d.isActiveAt(now) ||
                (d.status == SubstituteDelegationStatus.expired &&
                    !d.dataCollected)),
      )
      .toList();
});

/// Delega attiva (in corso) di cui il catechista locale è il Supplente.
final myActiveSubstitutionsProvider = Provider<List<SubstituteDelegation>>((
  ref,
) {
  final now = DateTime.now().toUtc();
  return ref
      .watch(mySubstitutionsProvider)
      .where((d) => d.isActiveAt(now))
      .toList();
});

/// Classi della propria anagrafica affiancate alle classi in supplenza
/// (la supplenza NON aggiunge il Supplente a `catechistIds`).
final visibleClassesProvider = Provider<List<SchoolClass>>((ref) {
  final mine = ref.watch(myClassesProvider);
  final mySubs = ref.watch(mySubstitutionsProvider);
  if (mySubs.isEmpty) return mine;

  final mineIds = mine.map((c) => c.id).toSet();
  final onlySub = mySubs.where((d) => !mineIds.contains(d.classId));
  final shadowClasses = ref
      .watch(classesStreamProvider)
      .maybeWhen(
        data: (classes) => classes
            .where((c) => onlySub.any((d) => d.classId == c.id))
            .toList(),
        orElse: () => const <SchoolClass>[],
      );
  return [...mine, ...shadowClasses];
});

/// Delega attiva per la classe corrente (usata per badge e restrizioni).
final currentSubstitutionProvider = Provider<SubstituteDelegation?>((ref) {
  final classId = ref.watch(currentClassProvider);
  if (classId == null) return null;
  final active = ref.watch(myActiveSubstitutionsProvider);
  for (final d in active) {
    if (d.classId == classId) return d;
  }
  return null;
});

/// True se la classe [classId] è attualmente in supplenza per il locale.
bool isClassInSubstitution(String classId, List<SubstituteDelegation> subs) {
  final now = DateTime.now().toUtc();
  return subs.any((d) => d.classId == classId && d.isActiveAt(now));
}
