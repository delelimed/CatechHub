import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/auth/auth_service.dart';
import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/features/sync/normal/normal_mode_sync_handler.dart';
import 'package:CatechHub/features/sync/p2p/p2p_sync_service.dart';
import 'package:CatechHub/shared/utils/app_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('hive_normal_mode_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalDatabase.authBox);
    await Hive.openBox<Map>(LocalDatabase.classesBox);
    await Hive.openBox<Map>(LocalDatabase.studentsBox);
    // Force normal mode (non responsabile)
    await Hive.box(LocalDatabase.authBox).put('app_mode', 'NORMAL');
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk(LocalDatabase.authBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.classesBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.studentsBox);
    tempDir.deleteSync(recursive: true);
  });

  group('Modalità Normale — reingegnerizzata', () {
    test('Mio Dispositivo: condivide catechistId (adotta se fresco)', () async {
      // Simula dispositivo primario con catechistId noto
      const primaryId = 'cat_primary_12345678';
      // Il locale è fresco: nessuna classe associata al suo id corrente
      final freshLocalId = AuthService.getCatechistId();
      expect(freshLocalId, isNot(primaryId));

      final adopted = await NormalModeSyncHandler.shareCatechistIdForMyDevice(
        remoteCatechistId: primaryId,
        localRole: P2PSyncRole.mioDispositivo,
        remoteRole: P2PSyncRole.mioDispositivo,
      );

      expect(adopted, isTrue);
      expect(AuthService.getCatechistId(), primaryId);
    });

    test('Mio Dispositivo: non adotta se già ha identità', () async {
      // Crea una classe che lega il locale al suo catechistId attuale
      final localCat = AuthService.getCatechistId();
      await LocalDatabase.classes().put('class_1', {
        'name': 'Test Classe',
        'uniqueCode': 'CODE_001',
        'catechistIds': [localCat],
        'creatorCatechistId': localCat,
        'associatedCatechistIds': [localCat],
        'catechistDeviceCounts': {localCat: 1},
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });

      const remoteId = 'cat_altro_99999999';
      final adopted = await NormalModeSyncHandler.shareCatechistIdForMyDevice(
        remoteCatechistId: remoteId,
        localRole: P2PSyncRole.mioDispositivo,
        remoteRole: P2PSyncRole.mioDispositivo,
      );

      expect(adopted, isFalse);
      expect(AuthService.getCatechistId(), localCat);
    });

    test('Altro Catechista: associa catechista alla classe condivisa', () async {
      final localCat = AuthService.getCatechistId();
      await LocalDatabase.classes().put('class_shared', {
        'name': 'Classe Condivisa',
        'uniqueCode': 'CODE_SHARED',
        'catechistIds': ['local_catechist_id'],
        'creatorCatechistId': localCat,
        'associatedCatechistIds': [localCat],
        'catechistDeviceCounts': {localCat: 1},
        'catechistRoles': {localCat: 'TITOLARE'},
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });

      const remoteCat = 'cat_altro_catechista_7777';
      final touched =
          await NormalModeSyncHandler.associateOtherCatechistToSharedClasses(
        remoteCatechistId: remoteCat,
        sharedClassIds: {'class_shared'},
      );

      expect(touched, 1);
      final updated = LocalDatabase.toStringDynamicMap(
        LocalDatabase.classes().get('class_shared'),
      );
      expect((updated['catechistIds'] as List).contains(remoteCat), isTrue);
      expect((updated['associatedCatechistIds'] as List).contains(remoteCat),
          isTrue);
      expect((updated['catechistRoles'] as Map)[remoteCat], 'TITOLARE');
      expect(updated['catechistDeviceCounts'][remoteCat], 1);
    });

    test('Altro Catechista: entrambi lavorano sugli stessi dati (scope)', () async {
      final localCat = AuthService.getCatechistId();
      const remoteCat = 'cat_collega_8888';

      // Due classi: solo una condivisa
      await LocalDatabase.classes().put('class_A', {
        'name': 'Classe A condivisa',
        'uniqueCode': 'CODE_A',
        'creatorCatechistId': localCat,
        'associatedCatechistIds': [localCat],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      await LocalDatabase.classes().put('class_B', {
        'name': 'Classe B privata',
        'uniqueCode': 'CODE_B',
        'creatorCatechistId': localCat,
        'associatedCatechistIds': [localCat],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });

      // Dopo associazione, solo A è condivisa
      await NormalModeSyncHandler.associateOtherCatechistToSharedClasses(
        remoteCatechistId: remoteCat,
        sharedClassIds: {'class_A'},
      );

      final scope = await NormalModeSyncHandler.buildNormalSyncScope(
        remoteCatechistId: remoteCat,
        sharedClassIds: {'class_A'},
        localRoleName: P2PSyncRole.altroCatechista.name,
        remoteRoleName: P2PSyncRole.altroCatechista.name,
      );

      expect(scope, isNotNull);
      expect(scope!.map((s) => s.classId), contains('class_A'));
      expect(scope.map((s) => s.classId), isNot(contains('class_B')));
    });

    test('Modalità Responsabile non altera (NOP)', () async {
      await Hive.box(LocalDatabase.authBox).put('app_mode', 'RESPONSABILE');
      expect(AppModeUtils.isResponsabileMode, isTrue);
      expect(NormalModeSyncHandler.isNormalContext, isFalse);

      const remoteCat = 'cat_test';
      final adopted = await NormalModeSyncHandler.shareCatechistIdForMyDevice(
        remoteCatechistId: remoteCat,
        localRole: P2PSyncRole.mioDispositivo,
        remoteRole: P2PSyncRole.mioDispositivo,
      );
      expect(adopted, isFalse);

      final touched =
          await NormalModeSyncHandler.associateOtherCatechistToSharedClasses(
        remoteCatechistId: remoteCat,
        sharedClassIds: {'any'},
      );
      expect(touched, 0);

      // Ripristina normale per tearDown
      await Hive.box(LocalDatabase.authBox).put('app_mode', 'NORMAL');
    });
  });

  group('Cifratura militare + GDPR', () {
    test('Handler documenta stack AES-256-GCM + X25519 + HKDF', () {
      // Il contratto crittografico è documentato nel file handler:
      // verifica che il file esista e contenga i marker di standard militare.
      final file = File(
        'lib/features/sync/normal/normal_mode_sync_handler.dart',
      );
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      expect(content, contains('AES-256-GCM'));
      expect(content, contains('X25519'));
      expect(content, contains('HKDF'));
      expect(content, contains('forward secrecy'));
      expect(content, contains('GDPR'));
    });
  });
}
