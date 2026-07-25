import 'package:flutter_riverpod/legacy.dart';
import '../services/qr_data_service.dart';

// Provider temporaneo per passare i dati di condivisione tra pagine
final dataShareDataProvider = StateProvider<Map<String, dynamic>?>((ref) => null);
final dataSharePinProvider = StateProvider<String?>((ref) => null);

// Opzioni di condivisione selezionate dall'utente (per flusso differenziale)
final dataShareOptionsProvider = StateProvider<DataShareOptions?>((ref) => null);

// Indice remoto scansionato (usato dal lato mittente per calcolare il diff)
final scannedRemoteIndexProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

// Dati differenziali preparati (il risultato del confronto)
final differentialDataProvider = StateProvider<Map<String, dynamic>?>((ref) => null);
