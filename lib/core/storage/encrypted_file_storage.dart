import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'local_database.dart';

/// Salva file allegati (immagini, PDF, documenti) nella directory privata
/// dell'app, cifrati con la stessa chiave AES usata da Hive.
///
/// CONTESTO PROGETTO:
/// I metadati degli allegati (nome, tipo, data) sono memorizzati nel Box Hive
/// `attachments_box`. I file fisici, invece, vengono scritti qui in una
/// cartella `secure_vault` sotto ApplicationSupportDirectory, cifrati byte per
/// byte con [LocalDatabase.encryptBytes]. Questo garantisce che:
/// 1. I file non siano leggibili nemmeno con accesso fisico al dispositivo.
/// 2. La gestione sia indipendente dal Box Hive (un file corrotto non intacca
///    il database dei metadati, e viceversa).
/// 3. La pulizia sia atomica: [DataDeletionService] coordina l'eliminazione
///    sia dei metadati che dei file fisici.
class EncryptedFileStorage {
  /// Dopo l'ottimizzazione gli allegati restano sotto questa soglia.
  /// 6 MB = immagine 1600px JPEG qualità 75 (~300-500 KB) + margine per PDF
  /// ottimizzati manualmente dall'utente.
  static const maxFileBytes = 6 * 1024 * 1024;
  static const _vaultFolder = 'secure_vault';

  /// Restituisce la directory `secure_vault` sotto ApplicationSupportDirectory.
  /// La posizione varia per OS: Windows usa %APPDATA%, Android usa
  /// getFilesDir(), iOS usa NSApplicationSupportDirectory.
  /// La directory viene creata se non esiste.
  static Future<Directory> _vaultDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_vaultFolder');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Costruisce il path completo per un file vault.
  /// Il naming usa l'ID univoco dell'allegato (generato da LocalDatabase.newId())
  /// con estensione .vault per evitare confusione con file normali.
  /// I separatori di path nello storageId vengono sanitizzati per evitare
  /// PathNotFoundException su POSIX quando il filesystem non riesce a risolvere
  /// directory intermedie inesistenti (es. storageId = 'document/1537').
  static Future<File> _fileFor(String storageId) async {
    final dir = await _vaultDirectory();
    final safeId = storageId.replaceAll(RegExp(r'[/\\]'), '_');
    return File('${dir.path}/$safeId.vault');
  }

  /// Scrive [plainBytes] cifrati su disco.
  /// [storageId] è l'ID univoco dell'allegato (deve matchare la chiave
  /// nel Box `attachments_box` per permettere la cancellazione coordinata).
  /// Lancia un'eccezione se il file supera [maxFileBytes] (limite di
  /// sicurezza per evitare di saturare lo storage del dispositivo).
  static Future<void> write(String storageId, Uint8List plainBytes) async {
    if (plainBytes.length > maxFileBytes) {
      throw Exception(
        'File troppo grande (max ${maxFileBytes ~/ (1024 * 1024)} MB)',
      );
    }
    final encrypted = LocalDatabase.encryptBytes(plainBytes);
    final file = await _fileFor(storageId);
    await file.writeAsBytes(encrypted, flush: true);
  }

  /// Legge e decifra un file vault.
  /// [storageId] deve corrispondere a un file .vault esistente.
  /// Lancia Exception se il file non esiste (dati orfani: può succedere se
  /// il Box Hive è stato cancellato ma i file vault no, o viceversa).
  static Future<Uint8List> read(String storageId) async {
    final file = await _fileFor(storageId);
    if (!await file.exists()) {
      throw Exception('File allegato non trovato');
    }
    final encrypted = await file.readAsBytes();
    return LocalDatabase.decryptBytes(encrypted);
  }

  /// Verifica se un file vault esiste su disco.
  /// Usato da AttachmentRepository prima di tentare la lettura.
  static Future<bool> exists(String storageId) async {
    return (await _fileFor(storageId)).exists();
  }

  /// Elimina un singolo file vault.
  /// Usato da [DataDeletionService] quando cancella allegati selettivamente.
  /// Non lancia eccezione se il file non esiste.
  static Future<void> delete(String storageId) async {
    final file = await _fileFor(storageId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Elimina TUTTI i file vault dalla directory secure_vault.
  /// Usato durante la cancellazione completa dei dati (impostazioni ->
  /// elimina tutto) o quando l'utente disinstalla l'app.
  static Future<void> deleteAll() async {
    final dir = await _vaultDirectory();
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      if (entity is File) {
        await entity.delete();
      }
    }
  }
}
