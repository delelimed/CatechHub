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
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart' as pc;

class BackupEncryptionService {
  static const int _version = 2;
  static const int _iterations = 210000;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _tagLengthBits = 128;
  static const int _keyLength = 32; // AES-256

/// Genera byte casuali crittograficamente sicuri.
  static Uint8List _secureRandomBytes(int length) {
    final random = pc.FortunaRandom()
      ..seed(pc.KeyParameter(Uint8List.fromList(
        List<int>.generate(32, (_) => DateTime.now().microsecondsSinceEpoch & 0xFF),
      )));

    return Uint8List.fromList(List<int>.generate(length, (_) => random.nextUint32() & 0xFF));
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
        pc.AEADParameters(pc.KeyParameter(key), _tagLengthBits, nonce, Uint8List(0)),
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
    try {
      final packageStr = utf8.decode(base64Decode(encryptedPackage));
      final package = jsonDecode(packageStr) as Map<String, dynamic>;

      if (package['v'] != _version) {
        throw Exception('Versione backup non supportata: ${package['v']}');
      }

      final iterations = package['iter'] as int;
      if (iterations != _iterations) {
        throw Exception('Iterazioni KDF non corrispondenti: $iterations (attese $_iterations)');
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
            Uint8List(0),
          ),
        );

      final decrypted = cipher.process(base64Decode(dataB64));
      return utf8.decode(decrypted);
    } on FormatException catch (e) {
      throw Exception('Formato backup non valido: $e');
    } on pc.InvalidCipherTextException catch (_) {
      throw Exception('PIN non corretto o dati corrotti');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Errore decifratura: $e');
    }
  }

  /// Verifica se [pin] decifra correttamente [encryptedPackage] SENZA restituire i dati.
  /// Usato per validare il PIN prima dell'import completo.
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
  /// Il PIN deve essere almeno 4 cifre, solo numeri.
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
                    ? 'Scegli un PIN numerico (min 4 cifre) per proteggere il file di backup. '
                      'Questo PIN serve SOLO per questo backup e non è il PIN del telefono.'
                    : 'Inserisci il PIN usato per cifrare questo backup.',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 12,
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
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() => showError = false),
              ),
              if (isExport) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 12,
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
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                if (pin.length < 4) {
                  setState(() {
                    showError = true;
                    errorText = 'Il PIN deve essere di almeno 4 cifre';
                  });
                  return;
                }
                if (isExport && pin != confirmController.text.trim()) {
                  setState(() {
                    showError = true;
                    errorText = 'I PIN non coincidono';
                  });
                  return;
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