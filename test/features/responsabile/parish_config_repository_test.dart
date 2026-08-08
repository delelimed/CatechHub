// ============================================================================
// TEST: ParishConfigRepository
// Copre: lettura default, salvataggio, permessi suddivisi per ruolo.
// ============================================================================
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/features/responsabile/parish_config_repository.dart';
import 'package:CatechHub/shared/models/parish_config.dart';
import 'package:CatechHub/shared/models/user_role.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('hive_parish_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalDatabase.authBox);
    await Hive.openBox(LocalDatabase.parishConfigBox);
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk(LocalDatabase.parishConfigBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.authBox);
    tempDir.deleteSync(recursive: true);
  });

  group('ParishConfigRepository', () {
    test('ritorna ParishConfig.empty se nessuna configurazione salvata', () {
      final repo = ParishConfigRepository();
      expect(repo.getConfig(), ParishConfig.empty);
    });

    test('salva e rilegge una configurazione', () async {
      await UserRole.setCurrent(UserRole.responsabile);
      final repo = ParishConfigRepository();
      final config = const ParishConfig(
        isResponsabileModeActive: true,
        nomeParrocchia: 'Parrocchia San Giovanni',
        diocesi: 'Diocesi di Roma',
        annoCatechisticoCorrente: '2026-2027',
        durataValiditaConsensoMesi: 18,
      );
      await repo.save(config);
      expect(repo.getConfig(), config);
    });

    test('solo il Responsabile può scrivere la configurazione', () async {
      await UserRole.setCurrent(UserRole.catechista);
      final repo = ParishConfigRepository();
      final config = const ParishConfig(nomeParrocchia: 'X');
      await expectLater(
        repo.save(config),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('setResponsabileModeActive abilita la modalità conservando il resto',
        () async {
      await UserRole.setCurrent(UserRole.responsabile);
      final repo = ParishConfigRepository();
      await repo.save(const ParishConfig(nomeParrocchia: 'Parrocchia X'));

      final updated = await repo.setResponsabileModeActive(true);
      expect(updated.isResponsabileModeActive, isTrue);
      expect(updated.nomeParrocchia, 'Parrocchia X');
      expect(repo.getConfig().isResponsabileModeActive, isTrue);
    });

    test('reset riporta alla configurazione vuota', () async {
      await UserRole.setCurrent(UserRole.responsabile);
      final repo = ParishConfigRepository();
      await repo.save(const ParishConfig(nomeParrocchia: 'X'));
      await repo.reset();
      expect(repo.getConfig(), ParishConfig.empty);
    });
  });
}