// ═══════════════════════════════════════════════════════════════════════════════
// hardware_security_exception.dart — CatechHub (Eccezione Sicurezza Hardware)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Eccezione personalizzata sollevata quando il dispositivo non soddisfa i
// requisiti di sicurezza hardware (TEE/StrongBox/Keymaster non disponibili).
//
// Viene intercettata in main.dart per mostrare la SecurityBlockScreen e
// bloccare l'avvio dell'applicazione.
// ═══════════════════════════════════════════════════════════════════════════════

/// Eccezione personalizzata per fallimenti sicurezza hardware.
///
/// Viene sollevata quando:
/// - Il dispositivo non ha TEE (Trusted Execution Environment) disponibile
/// - StrongBox/Keymaster hardware-backed non è accessibile
/// - FlutterSecureStorage non può usare Android Keystore (encryptedSharedPreferences)
/// - La generazione/lettura della Master Key fallisce per motivi hardware
///
/// main.dart intercetta questa eccezione e mostra SecurityBlockScreen con
/// messaggio "Dispositivo non conforme ai requisiti di sicurezza hardware".
class HardwareSecurityException implements Exception {
  /// Messaggio per l'utente finale (italiano, non tecnico).
  final String userMessage;

  /// Dettaglio tecnico per debug/log (opzionale).
  final String? technicalDetail;

  const HardwareSecurityException(this.userMessage, {this.technicalDetail});

  @override
  String toString() => 'HardwareSecurityException: $userMessage'
      '${technicalDetail != null ? ' (Dettaglio: $technicalDetail)' : ''}';
}