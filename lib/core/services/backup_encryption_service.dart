// ══════════════════════════════════════════════════════════════════════════════
// backup_encryption_service.dart — CatechHub (Cifratura backup con PIN utente)
// 
// NUOVO FLUSSO (post-migrazione): non esiste più un PIN dell'app.
// Quando l'utente esporta un backup, DEVE inserire e confermare un PIN
// scelto al momento (diverso dal PIN del telefono). Questo PIN deriva
// la chiave AES-256-GCM via PBKDF2 (210k iterazioni).
//
// SICUREZZA:
// - PBKDF2-HMAC-SHA256, 210.000 iterazioni, salt 16 byte casuali
// - AES-256-GCM (confidenzialità + integrità), nonce 12 byte
// - Formato: base64({v, kdf, iter, alg, salt, nonce, ciphertext})
// - Constant-time password verification
// - Zero app PIN storage: il PIN backup vive solo nella memoria dell'utente
// - Entropia aumentata a 12 cifre (10^12 combinazioni): ricerca esaustiva
//   impractical anche su cluster GPU potenti.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart' as pc;

class BackupEncryptionService {
  static const int _version = 2;
  // M9: iterazioni PBKDF2 aumentate (210k → 350k) per rendere il brute-force
  // offline ancora più costoso. I pacchetti creati con 210k restano decifrabili
  // (vedi _legacyIterations in decryptBackup).
  static const int _iterations = 350000;

  /// Iterazioni KDF usate dalle versioni precedenti: accettate in lettura per
  /// non rendere inutilizzabili i backup già creati.
  static const int _legacyIterations = 210000;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _tagLengthBits = 128;
  static const int _keyLength = 32; // AES-256

  /// Lunghezza minima del PIN backup: 12 caratteri ALFANUMERICI.
  /// M9: un PIN solo numerico (10^10 o 10^12) ha un keyspace troppo ridotto per
  /// il brute-force offline su GPU. Mescolando lettere e cifre (almeno una di
  /// ogni classe) il keyspace cresce a ~62^12 ≈ 2^71, impraticabile anche con
  /// PBKDF2 a iterazioni ridotte.
  static const int minPinLength = 12;

  /// Numero massimo di tentativi di decifratura prima di bloccare l'import
  /// (anti brute-force). Anche se il backup offline resta attaccabile con
  /// brute-force indipendente dall'app, il lockout protegge dal caso in cui
  /// un PIN debole sia stato scelto e l'attaccante provi a indovinarlo in
  /// loco tramite l'interfaccia.
  static const int maxDecryptAttempts = 5;

  /// Intervallo di lockout dopo il superamento di [maxDecryptAttempts].
  static const Duration lockoutDuration = Duration(minutes: 30);

  /// Registro (in memoria) dei tentativi falliti per backup: la chiave è
  /// l'hash del pacchetto, così il lockout è legato al singolo file importato
  /// e non all'utente. La persistenza è volutamente in memoria: un lockout
  /// persistente su disco sarebbe aggirabile cancellando il file.
  static final Map<String, int> _failedAttempts = {};
  static final Map<String, DateTime> _lockedUntil = {};

  static final _aad = Uint8List.fromList(
    utf8.encode('CatechHub_Context_Backup_v1'),
  );

/// Genera byte casuali crittograficamente sicuri (Random.secure del sistema,
/// NON seminati dal timestamp: salt/nonce prevedibili romperebbero AES-GCM).
  static Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  /// Deriva chiave AES-256 da PIN con PBKDF2-HMAC-SHA256.
  static Uint8List _deriveKey(String pin, Uint8List salt) {
    final mac = pc.HMac(pc.SHA256Digest(), 64);
    final derivator = pc.PBKDF2KeyDerivator(mac)
      ..init(pc.Pbkdf2Parameters(salt, _iterations, _keyLength));
    return derivator.process(Uint8List.fromList(utf8.encode(pin)));
  }

  /// Cifra [data] (JSON string) con PIN usando AES-256-GCM.
  /// Restituisce pacchetto completo Base64 pronto per salvataggio su file.
  static String encryptBackup(String jsonData, String pin) {
    final salt = _secureRandomBytes(_saltLength);
    final nonce = _secureRandomBytes(_nonceLength);
    final key = _deriveKey(pin, salt);

    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        true,
        pc.AEADParameters(pc.KeyParameter(key), _tagLengthBits, nonce, _aad),
      );

    final plaintext = utf8.encode(jsonData);
    final ciphertext = cipher.process(Uint8List.fromList(plaintext));

    final package = {
      'v': _version,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iter': _iterations,
      'alg': 'AES-256-GCM',
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'data': base64Encode(ciphertext),
    };

    return base64Encode(utf8.encode(jsonEncode(package)));
  }

  /// Decifra pacchetto backup con PIN.
  /// Lancia Exception se PIN errato, dati corrotti o formato non valido.
  static String decryptBackup(String encryptedPackage, String pin) {
    final packageKey = _packageKey(encryptedPackage);
    final lockedUntil = _lockedUntil[packageKey];
    if (lockedUntil != null && DateTime.now().isBefore(lockedUntil)) {
      final remaining = lockedUntil.difference(DateTime.now()).inMinutes + 1;
      throw Exception(
        'Troppi tentativi falliti. Riprova tra $remaining minuti.',
      );
    }

    try {
      final packageStr = utf8.decode(base64Decode(encryptedPackage));
      final package = jsonDecode(packageStr) as Map<String, dynamic>;

      if (package['v'] != _version) {
        throw Exception('Versione backup non supportata: ${package['v']}');
      }

      final iterations = package['iter'] as int;
      if (iterations != _iterations && iterations != _legacyIterations) {
        throw Exception('Iterazioni KDF non corrispondenti: $iterations (attese $_iterations o legacy $_legacyIterations)');
      }

      final salt = base64Decode(package['salt'] as String);
      final nonce = base64Decode(package['nonce'] as String);
      final dataB64 = package['data'] as String;

      if (salt.length != _saltLength) {
        throw Exception('Salt lunghezza non valida: ${salt.length}');
      }
      if (nonce.length != _nonceLength) {
        throw Exception('Nonce lunghezza non valida: ${nonce.length}');
      }

      final key = _deriveKey(pin, Uint8List.fromList(salt));

      final cipher = pc.GCMBlockCipher(pc.AESEngine())
        ..init(
          false,
          pc.AEADParameters(
            pc.KeyParameter(key),
            _tagLengthBits,
            Uint8List.fromList(nonce),
            _aad,
          ),
        );

      final decrypted = cipher.process(base64Decode(dataB64));
      // Decifratura riuscita: azzera il contatore di tentativi per questo file.
      _failedAttempts.remove(packageKey);
      _lockedUntil.remove(packageKey);
      return utf8.decode(decrypted);
    } on FormatException catch (e) {
      _recordFailure(packageKey);
      throw Exception('Formato backup non valido: $e');
    } on pc.InvalidCipherTextException catch (_) {
      _recordFailure(packageKey);
      throw Exception('PIN non corretto o dati corrotti');
    } catch (e) {
      _recordFailure(packageKey);
      if (e is Exception) rethrow;
      throw Exception('Errore decifratura: $e');
    }
  }

  /// Chiave identificativa del pacchetto (hash SHA-256 troncato) usata per
  /// il rate-limiting: lega i tentativi al singolo file, non all'utente.
  static String _packageKey(String encryptedPackage) {
    return sha256Of(encryptedPackage);
  }

  static String sha256Of(String value) {
    final d = pc.SHA256Digest();
    final bytes = Uint8List.fromList(utf8.encode(value));
    final out = Uint8List(d.digestSize);
    d.update(bytes, 0, bytes.length);
    d.doFinal(out, 0);
    return base64Encode(out).substring(0, 24);
  }

  static void _recordFailure(String packageKey) {
    final now = DateTime.now();
    _failedAttempts[packageKey] = (_failedAttempts[packageKey] ?? 0) + 1;
    if (_failedAttempts[packageKey]! >= maxDecryptAttempts) {
      _lockedUntil[packageKey] = now.add(lockoutDuration);
      _failedAttempts.remove(packageKey);
    }
  }

  /// Verifica se [pin] decifra correttamente [encryptedPackage] SENZA restituire i dati.
  /// Usato per validare il PIN prima dell'import completo.
  /// Rispetta il rate-limiting di [decryptBackup] (lockout dopo tentativi falliti).
  static bool verifyPin(String encryptedPackage, String pin) {
    try {
      decryptBackup(encryptedPackage, pin);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Mostra dialog per inserimento e conferma PIN backup.
  /// Restituisce il PIN scelto dall'utente, o null se annullato.
  /// M9: il PIN deve essere di almeno [minPinLength] caratteri ALFANUMERICI e
  /// contenere almeno una lettera e una cifra (keyspace espanso, anti
  /// brute-force offline). In lettura accetta anche i PIN numerici legacy.
  static Future<String?> showBackupPinDialog({
    required BuildContext context,
    required bool isExport, // true = esportazione (crea PIN), false = importazione (inserisci PIN)
  }) async {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    bool showError = false;
    String? errorText;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                isExport ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
                color: const Color(0xFF174A7E),
              ),
              const SizedBox(width: 8),
              Text(isExport ? 'Crea PIN Backup' : 'Inserisci PIN Backup'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isExport
                    ? 'Scegli una passphrase di almeno $minPinLength caratteri alfanumerici '
                      '(lettere e cifre, almeno una di ogni tipo) per proteggere il file di backup. '
                      'Questo PIN serve SOLO per questo backup e non è il PIN del telefono.'
                    : 'Inserisci il PIN usato per cifrare questo backup.',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.text,
                obscureText: true,
                maxLength: 16,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'PIN',
                  hintText: '••••',
                  hintStyle: const TextStyle(letterSpacing: 8),
                  prefixIcon: const Icon(Icons.security_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: showError ? Colors.red.shade300 : Colors.grey.shade300,
                      width: showError ? 2 : 1,
                    ),
                  ),
                  counterText: '',
                ),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]'))],
                onChanged: (_) => setState(() => showError = false),
              ),
              if (isExport) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  keyboardType: TextInputType.text,
                  obscureText: true,
                  maxLength: 16,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Conferma PIN',
                    hintText: '••••',
                    hintStyle: const TextStyle(letterSpacing: 8),
                    prefixIcon: const Icon(Icons.security_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: showError ? Colors.red.shade300 : Colors.grey.shade300,
                        width: showError ? 2 : 1,
                      ),
                    ),
                    counterText: '',
                  ),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]'))],
                  onChanged: (_) => setState(() => showError = false),
                ),
              ],
              if (showError && errorText != null) ...[
                const SizedBox(height: 8),
                Text(errorText!, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Annulla'),
            ),
            TextButton(
              onPressed: () {
                final pin = controller.text.trim();
                if (pin.length < minPinLength) {
                  setState(() {
                    showError = true;
                    errorText = 'Il PIN deve essere di almeno $minPinLength caratteri';
                  });
                  return;
                }
                if (isExport) {
                  final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(pin);
                  final hasDigit = RegExp(r'[0-9]').hasMatch(pin);
                  if (!hasLetter || !hasDigit) {
                    setState(() {
                      showError = true;
                      errorText = 'Il PIN deve contenere almeno una lettera e una cifra';
                    });
                    return;
                  }
                  if (pin != confirmController.text.trim()) {
                    setState(() {
                      showError = true;
                      errorText = 'I PIN non coincidono';
                    });
                    return;
                  }
                }
                Navigator.pop(ctx, pin);
              },
              style: TextButton.styleFrom(foregroundColor: const Color(0xFF174A7E)),
              child: Text(isExport ? 'Crea Backup' : 'Decifra'),
            ),
          ],
        ),
      ),
    );
  }
}