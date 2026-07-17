import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'planning_repository.dart';

/// Provider Riverpod singleton per [PlanningRepository].
///
/// Utilizzato in tutta la sezione Programmazione per accedere alle
/// operazioni CRUD sugli incontri/riunioni. Dipende esclusivamente
/// dal box Hive `planning` gestito da [PlanningRepository].
final planningRepoProvider = Provider<PlanningRepository>(
  (ref) => PlanningRepository(),
);