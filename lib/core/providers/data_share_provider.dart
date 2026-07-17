// ══════════════════════════════════════════════════════════════════════════════
// data_share_provider.dart — CatechHub (provider condivisione dati tra pagine)
//
// Provider Riverpod temporanei per passare dati e PIN tra le pagine del
// flusso di condivisione dati (QR/Bluetooth).
//
// CONTESTO PROGETTO:
//   Il flusso di condivisione dati attraversa più pagine:
//     1. DataShareSelectionPage — sceglie se inviare o ricevere
//     2. DataShareSendPage — genera QR o avvia trasmissione
//     3. DataShareReceivePage — scansiona QR o attende connessione
//
//   Questi provider evitano di dover passare oggetti complessi tramite
//   GoRouter state.extra, che non sarebbe persistente tra route changes.
//
//   dataShareDataProvider: contiene i dati da condividere/ricevuti
//   dataSharePinProvider: contiene il PIN per cifratura/decifratura
// ══════════════════════════════════════════════════════════════════════════════

//import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

// Provider temporaneo per passare i dati di condivisione tra pagine
final dataShareDataProvider = StateProvider<Map<String, dynamic>?>((ref) => null);
final dataSharePinProvider = StateProvider<String?>((ref) => null);
