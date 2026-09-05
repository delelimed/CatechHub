/// Repository CRUD per gli allegati di CateREG.
///
/// Gestisce l'intero ciclo di vita di un allegato:
///
/// - **Salvataggio**: i byte in ingresso vengono ottimizzati (ridimensionamento
///   immagini a max 1600px, conversione a JPEG) tramite [AttachmentOptimizer],
///   poi crittografati e scritti su disco con [EncryptedFileStorage]. I metadati
///   (nome, tipo, hash SHA-256, dimensione effettiva salvata) sono persistiti
///   in [LocalDatabase] nella collection `attachments`.
///
/// - **Lettura**: [readBytes] restituisce il contenuto decrittografato come
///   [Uint8List] per la visualizzazione in [AttachmentViewerPage].
///
/// - **Eliminazione**: rimuove sia il file crittografato dal vault sia i metadati
///   dal database locale. L'eliminazione di massa ([deleteAllForParent]) serve
///   quando un'entità padre (es. una pratica) viene cancellata.
///
/// - **Aggiornamento**: [updateAttachmentName] permette di rinominare un allegato
///   senza toccare il file cifrato.
///
/// Ogni allegato è associato a un'entità padre tramite [parentId] e [parentType],
/// permettendo di recuperare tutti gli allegati di una pratica, fattura, o altra
/// entità del gestionale CateREG.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/crypto_utils.dart';
import '../../core/storage/attachment_optimizer.dart';
import '../../core/storage/encrypted_file_storage.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models/attachment_model.dart';
import '../../shared/utils/auth_utils.dart';

/// Provider Riverpod per [AttachmentsRepository].
///
/// L'istanza è singleton (Provider, non Family) perché il repository non ha
/// parametri di configurazione: opera sempre sulla stessa collection del
/// database locale e sullo stesso vault crittografato.
final attachmentsRepositoryProvider = Provider<AttachmentsRepository>((ref) {
  return AttachmentsRepository();
});

class AttachmentsRepository {
  final _box = LocalDatabase.attachments();

  Stream<List<Attachment>> watchForParent({
    required String parentId,
    required String parentType,
  }) {
    return LocalDatabase.watchList(
      _box,
      (id, data) => Attachment.fromMap(id, data),
    ).map((attachments) => _filterAndSort(attachments, parentId, parentType));
  }

  List<Attachment> listForParent({
    required String parentId,
    required String parentType,
  }) {
    final all = LocalDatabase.values(
      _box,
      (id, data) => Attachment.fromMap(id, data),
    );
    return _filterAndSort(all, parentId, parentType);
  }

  List<Attachment> _filterAndSort(
    List<Attachment> attachments,
    String parentId,
    String parentType,
  ) {
    return attachments
        .where((a) => a.parentId == parentId && a.parentType == parentType)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<Attachment> addFromBytes({
    required String parentId,
    required String parentType,
    required String name,
    required String mimeType,
    required Uint8List bytes,
    String? description,
    String? classUniqueCode,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('Il file selezionato è vuoto');
    }

    final optimized = await AttachmentOptimizer.optimize(
      bytes: bytes,
      mimeType: mimeType,
      originalName: name,
    );

    final id = LocalDatabase.newId('attachment');
    await EncryptedFileStorage.write(id, optimized.bytes);

    final now = DateTime.now();
    final code =
        classUniqueCode ?? _lookupClassUniqueCode(parentId, parentType);
    final attachment = Attachment(
      id: id,
      parentId: parentId,
      parentType: parentType,
      name: optimized.name,
      mimeType: optimized.mimeType,
      size: optimized.savedBytes,
      createdAt: now,
      updatedAt: now,
      fileHash: sha256HexBytesSync(optimized.bytes),
      classUniqueCode: code,
      description: description,
      lastModifiedBy: getCurrentCatechistName(),
    );

    await _box.put(id, attachment.toMap());
    return attachment;
  }

  /// Ricava il classUniqueCode dal parentId+parentType.
  String? _lookupClassUniqueCode(String parentId, String parentType) {
    switch (parentType) {
      case 'student':
        final studentData = LocalDatabase.students().get(parentId);
        if (studentData == null) return null;
        final studentMap = LocalDatabase.toStringDynamicMap(studentData);
        final classId = studentMap['classId'] as String?;
        if (classId == null || classId.isEmpty) return null;
        final classData = LocalDatabase.classes().get(classId);
        if (classData == null) return null;
        final classMap = LocalDatabase.toStringDynamicMap(classData);
        return classMap['uniqueCode'] as String?;
      case 'meeting':
        final meetingData = LocalDatabase.planning().get(parentId);
        if (meetingData == null) return null;
        final meetingMap = LocalDatabase.toStringDynamicMap(meetingData);
        final code = meetingMap['classUniqueCode'] as String?;
        if (code != null && code.isNotEmpty) return code;
        final classId = meetingMap['classId'] as String?;
        if (classId == null || classId.isEmpty) return null;
        final classData = LocalDatabase.classes().get(classId);
        if (classData == null) return null;
        final classMap = LocalDatabase.toStringDynamicMap(classData);
        return classMap['uniqueCode'] as String?;
      case 'catechesi':
        // Le catechesi non hanno classId; classUniqueCode può essere passato
        return null;
      default:
        return null;
    }
  }

  Future<Attachment> addFromPath({
    required String parentId,
    required String parentType,
    required String filePath,
    required String name,
    required String mimeType,
    String? description,
    String? classUniqueCode,
  }) async {
    final bytes = await File(filePath).readAsBytes();
    return addFromBytes(
      parentId: parentId,
      parentType: parentType,
      name: name,
      mimeType: mimeType,
      bytes: bytes,
      description: description,
      classUniqueCode: classUniqueCode,
    );
  }

  Future<Uint8List> readBytes(String attachmentId) {
    return EncryptedFileStorage.read(attachmentId);
  }

  Future<void> deleteAttachment(String attachmentId) async {
    // Fase 3 — item 8: wipe sicuro del file vault (sovrascrittura + delete).
    await EncryptedFileStorage.deleteSecure(attachmentId);
    await _box.delete(attachmentId);
  }

  Future<void> deleteAllForParent({
    required String parentId,
    required String parentType,
  }) async {
    final items = listForParent(parentId: parentId, parentType: parentType);
    for (final item in items) {
      await deleteAttachment(item.id);
    }
  }

  Future<void> updateAttachmentName({
    required String attachmentId,
    required String name,
  }) async {
    final data = _box.get(attachmentId) as Map<String, dynamic>?;
    if (data == null) return;
    data['name'] = name;
    data['lastModifiedBy'] = getCurrentCatechistName();
    data['updatedAt'] = DateTime.now().toIso8601String();
    await _box.put(attachmentId, data);
  }
}
