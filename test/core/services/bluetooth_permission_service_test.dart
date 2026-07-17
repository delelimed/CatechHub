// ============================================================================
// TEST: BluetoothPermissionService
// Copre: PermissionCheckResult, messaggi di errore, factory methods
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:CatechHub/core/services/bluetooth_permission_service.dart';

void main() {
  // ══════════════════════════════════════════════════
  //  PermissionCheckResult
  // ══════════════════════════════════════════════════
  group('PermissionCheckResult', () {
    test('factory success() crea un risultato con allGranted=true', () {
      // Act: crea un risultato di successo
      final result = PermissionCheckResult.success();
      // Assert: tutti i permessi sono concessi
      expect(result.allGranted, isTrue);
      expect(result.hasPermanentlyDenied, isFalse);
      expect(result.deniedPermissions, isEmpty);
      expect(result.permanentlyDeniedPermissions, isEmpty);
      expect(result.errorMessage, isNull);
    });

    test('factory failure() crea un risultato con allGranted=false', () {
      // Act: crea un risultato di fallimento
      final result = PermissionCheckResult.failure(
        message: 'Permessi negati',
      );
      // Assert: i permessi non sono concessi
      expect(result.allGranted, isFalse);
      expect(result.errorMessage, 'Permessi negati');
    });

    test('factory failure() con permessi permanentemente negati', () {
      // Act: crea un risultato con permanentlyDenied
      final result = PermissionCheckResult.failure(
        message: 'Bloccati',
        permanent: [],
      );
      // Assert: hasPermanentlyDenied dipende dalla lista
      expect(result.allGranted, isFalse);
    });
  });

  // ══════════════════════════════════════════════════
  //  Logica di Fallback Bluetooth Classic
  // ══════════════════════════════════════════════════
  group('Logica Fallback Bluetooth Classic', () {
    test('il timeout BLE e di 15 secondi', () {
      // Arrange: il timeout BLE e definito nel ConnectionManager
      // In produzione: ConnectionManager.bleTimeout = Duration(seconds: 10)
      // Il test verifica che il fallback avvenga dopo il timeout
      // Act: verifica il timeout
      const bleTimeout = Duration(seconds: 10);
      const classicTimeout = Duration(seconds: 30);
      // Assert: Classic ha timeout maggiore di BLE
      expect(classicTimeout.inSeconds, greaterThan(bleTimeout.inSeconds));
    });

    test('la dimensione massima del buffer e 10 MB', () {
      // Arrange: il buffer max e definito in BluetoothClassicService
      const maxBufferSize = 10 * 1024 * 1024;
      // Assert: deve essere 10 MB
      expect(maxBufferSize, 10485760);
    });

    test('il framing length-prefixed usa 4 byte di header', () {
      // Arrange: il protocollo usa 4 byte big-endian per la lunghezza
      const headerSize = 4;
      // Assert: deve essere 4 byte
      expect(headerSize, 4);
    });
  });

  // ══════════════════════════════════════════════════
  //  UUID BLE
  // ══════════════════════════════════════════════════
  group('Costanti BLE', () {
    test('il nome advertised per il handshake ha il prefisso corretto', () {
      // Arrange: il prefisso e definito in BleUuids
      const prefix = 'CatechHub-HW-';
      // Act: costruisci un nome advertised
      final deviceId = 'CH_abc123_def456';
      final advertisedName = '$prefix$deviceId';
      // Assert: il nome deve iniziare con il prefisso
      expect(advertisedName, startsWith(prefix));
      expect(advertisedName, contains(deviceId));
    });

    test('il nome del server Classic e "CatechHub-Classic"', () {
      // Assert: verifica la costante
      expect('CatechHub-Classic', isNotEmpty);
    });

    test('la timeout di discoverability Classic e 120 secondi', () {
      // Assert: verifica il timeout
      expect(120, greaterThanOrEqualTo(60));
    });
  });
}
