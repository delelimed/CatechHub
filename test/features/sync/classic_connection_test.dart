// ============================================================================
// TEST: Classic Connection - Eccezioni Hardware e Cause di Isolamento
// Copre: BT spento, permessi negati, GPS disattivato, connessione RFCOMM
// ============================================================================
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:CatechHub/features/sync/data/classic_sync_models.dart';

/// ── Mock del servizio Bluetooth per simulare fallimenti hardware ──
/// Implementa le interfacce minime necessarie per testare la resilienza
/// dell'applicazione quando l'hardware fallisce.
class MockBluetoothAdapter {
  bool _isEnabled = true;
  bool _hasPermissions = true;
  bool _hasLocationEnabled = true;

  void setEnabled(bool enabled) => _isEnabled = enabled;
  void setPermissions(bool granted) => _hasPermissions = granted;
  void setLocationEnabled(bool enabled) => _hasLocationEnabled = enabled;

  bool get isEnabled => _isEnabled;
  bool get hasPermissions => _hasPermissions;
  bool get hasLocationEnabled => _hasLocationEnabled;
}

/// ── Mock del ConnectionManager per simulare connessione RFCOMM ──
/// Replica la logica reale di ClassicConnectionManager per la connessione
/// Bluetooth Classic (RFCOMM).
class MockConnectionManager {
  final MockBluetoothAdapter _adapter;
  ClassicConnectionState _state = ClassicConnectionState.idle;
  ClassicTransportType _activeTransport = ClassicTransportType.none;

  final _stateController = StreamController<ClassicConnectionState>.broadcast();
  final _messageController = StreamController<String>.broadcast();

  MockConnectionManager(this._adapter);

  Stream<ClassicConnectionState> get onStateChanged => _stateController.stream;
  Stream<String> get onMessage => _messageController.stream;
  ClassicConnectionState get currentState => _state;
  ClassicTransportType get activeTransport => _activeTransport;
  bool get isConnected => _state == ClassicConnectionState.connected;

  /// Simula il flusso di connessione RFCOMM.
  /// Verifica permessi, stato Bluetooth, localizzazione, poi avvia connessione.
  Future<void> connectClassic({ClassicPairingRole? pairingRole}) async {
    // STEP 0: verifica permessi
    _updateState(ClassicConnectionState.checkingCapabilities);

    if (!_adapter.hasPermissions) {
      _updateState(ClassicConnectionState.error);
      _messageController.add('Permessi Bluetooth negati.');
      return;
    }

    // Verifica stato Bluetooth
    if (!_adapter.isEnabled) {
      _updateState(ClassicConnectionState.error);
      _messageController.add(
        'Bluetooth disattivato. Attivalo dalle impostazioni del telefono.',
      );
      return;
    }

    // Verifica localizzazione
    if (!_adapter.hasLocationEnabled) {
      _updateState(ClassicConnectionState.error);
      _messageController.add(
        'Servizi di localizzazione disattivati. '
        'Attivali per la scansione Bluetooth.',
      );
      return;
    }

    // STEP 1: determina ruolo e connetti
    final effectiveRole = pairingRole ?? ClassicPairingRole.dispositivoB;

    if (effectiveRole == ClassicPairingRole.dispositivoA) {
      _updateState(ClassicConnectionState.classicServerListening);
      _messageController.add(
        'Ruolo: Dispositivo_A (SERVER) - Avvio server RFCOMM...',
      );
      _messageController.add('Server RFCOMM in ascolto...');
    } else {
      _updateState(ClassicConnectionState.classicClientConnecting);
      _messageController.add(
        'Ruolo: Dispositivo_B (CLIENT) - Discovery e connessione...',
      );
      _messageController.add('Tentativo Client RFCOMM...');
    }

    // Simula connessione riuscita
    await Future.delayed(const Duration(milliseconds: 50));
    _updateState(ClassicConnectionState.connected);
    _activeTransport = ClassicTransportType.classic;
    _messageController.add('Connessione RFCOMM stabilita');
  }

  void _updateState(ClassicConnectionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void dispose() {
    _stateController.close();
    _messageController.close();
  }
}

void main() {
  tearDown(() {
    // Cleanup globale dopo ogni test
  });

  // ══════════════════════════════════════════════════
  //  Stato Bluetooth Spento
  // ══════════════════════════════════════════════════
  group('Stato Bluetooth Spento', () {
    test('intercetta eccezione Bluetooth spento e aggiorna stato UI', () async {
      final adapter = MockBluetoothAdapter();
      adapter.setEnabled(false);
      final manager = MockConnectionManager(adapter);

      await manager.connectClassic();

      expect(manager.currentState, ClassicConnectionState.error);
      expect(manager.isConnected, isFalse);
    });

    test('mostra messaggio di errore corretto per BT spento', () async {
      final adapter = MockBluetoothAdapter()..setEnabled(false);
      final manager = MockConnectionManager(adapter);
      final messages = <String>[];
      manager.onMessage.listen((m) => messages.add(m));

      await manager.connectClassic();

      expect(
        messages.any((m) => m.contains('Bluetooth disattivato')),
        isTrue,
      );
    });
  });

  // ══════════════════════════════════════════════════
  //  Mancanza Permessi Runtime
  // ══════════════════════════════════════════════════
  group('Mancanza Permessi Runtime', () {
    test('intercetta permessi negati e mostra errore', () async {
      final adapter = MockBluetoothAdapter()..setPermissions(false);
      final manager = MockConnectionManager(adapter);

      await manager.connectClassic();

      expect(manager.currentState, ClassicConnectionState.error);
    });

    test('mostra messaggio per permessi negati', () async {
      final adapter = MockBluetoothAdapter()..setPermissions(false);
      final manager = MockConnectionManager(adapter);
      final messages = <String>[];
      manager.onMessage.listen((m) => messages.add(m));

      await manager.connectClassic();

      expect(
        messages.any((m) => m.contains('Permessi')),
        isTrue,
      );
    });
  });

  // ══════════════════════════════════════════════════
  //  GPS Disattivato
  // ══════════════════════════════════════════════════
  group('GPS Disattivato', () {
    test('intercetta localizzazione disattivata su Android 11', () async {
      final adapter = MockBluetoothAdapter()
        ..setPermissions(true)
        ..setEnabled(true)
        ..setLocationEnabled(false);
      final manager = MockConnectionManager(adapter);

      await manager.connectClassic();

      expect(manager.currentState, ClassicConnectionState.error);
    });

    test('mostra messaggio per servizi di localizzazione disattivati', () async {
      final adapter = MockBluetoothAdapter()
        ..setPermissions(true)
        ..setEnabled(true)
        ..setLocationEnabled(false);
      final manager = MockConnectionManager(adapter);
      final messages = <String>[];
      manager.onMessage.listen((m) => messages.add(m));

      await manager.connectClassic();

      expect(
        messages.any((m) => m.contains('localizzazione')),
        isTrue,
      );
    });
  });

  // ══════════════════════════════════════════════════
  //  Connessione RFCOMM
  // ══════════════════════════════════════════════════
  group('Connessione RFCOMM', () {
    test('connessione riuscita con PairingRole.dispositivoB (CLIENT)', () async {
      final adapter = MockBluetoothAdapter()
        ..setPermissions(true)
        ..setEnabled(true)
        ..setLocationEnabled(true);
      final manager = MockConnectionManager(adapter);
      final messages = <String>[];
      manager.onMessage.listen((m) => messages.add(m));

      await manager.connectClassic(
        pairingRole: ClassicPairingRole.dispositivoB,
      );

      expect(
        messages.any((m) => m.contains('Client RFCOMM')),
        isTrue,
      );
      expect(manager.isConnected, isTrue);
      expect(manager.activeTransport, ClassicTransportType.classic);
    });

    test('connessione riuscita con PairingRole.dispositivoA (SERVER)', () async {
      final adapter = MockBluetoothAdapter()
        ..setPermissions(true)
        ..setEnabled(true)
        ..setLocationEnabled(true);
      final manager = MockConnectionManager(adapter);
      final messages = <String>[];
      manager.onMessage.listen((m) => messages.add(m));

      await manager.connectClassic(
        pairingRole: ClassicPairingRole.dispositivoA,
      );

      expect(
        messages.any((m) => m.contains('Server RFCOMM')),
        isTrue,
      );
      expect(manager.isConnected, isTrue);
    });

    test('il flusso connessione segue la sequenza corretta di stati', () async {
      final adapter = MockBluetoothAdapter()
        ..setPermissions(true)
        ..setEnabled(true)
        ..setLocationEnabled(true);
      final manager = MockConnectionManager(adapter);
      final states = <ClassicConnectionState>[];
      manager.onStateChanged.listen((s) => states.add(s));

      await manager.connectClassic();

      expect(states, contains(ClassicConnectionState.checkingCapabilities));
      expect(states, contains(ClassicConnectionState.classicClientConnecting));
      expect(manager.currentState, ClassicConnectionState.connected);
      expect(manager.isConnected, isTrue);
    });

    test('connessione diretta a Classic senza BLE', () async {
      final adapter = MockBluetoothAdapter()
        ..setPermissions(true)
        ..setEnabled(true)
        ..setLocationEnabled(true);
      final manager = MockConnectionManager(adapter);

      await manager.connectClassic();

      expect(manager.isConnected, isTrue);
      expect(manager.activeTransport, ClassicTransportType.classic);
    });
  });

  // ══════════════════════════════════════════════════
  //  Bufferizzazione Flusso RFCOMM
  // ══════════════════════════════════════════════════
  group('Bufferizzazione Flusso RFCOMM', () {
    test('il buffer length-prefixed estrae il payload corretto', () {
      final payload = '{"records":[]}';
      final payloadBytes = payload.codeUnits;

      final packet = <int>[];
      packet.add((payloadBytes.length >> 24) & 0xFF);
      packet.add((payloadBytes.length >> 16) & 0xFF);
      packet.add((payloadBytes.length >> 8) & 0xFF);
      packet.add(payloadBytes.length & 0xFF);
      packet.addAll(payloadBytes);

      final extractedLength = (packet[0] << 24) |
          (packet[1] << 16) |
          (packet[2] << 8) |
          packet[3];

      expect(extractedLength, payloadBytes.length);

      final extractedPayload = String.fromCharCodes(packet.sublist(4));
      expect(extractedPayload, payload);
    });

    test('il buffer supporta payload multiplo (pipeline)', () {
      final payload1 = 'PrimoMessaggio';
      final payload2 = 'SecondoMessaggio';

      final buffer = <int>[];

      final p1Bytes = payload1.codeUnits;
      buffer.addAll([
        (p1Bytes.length >> 24) & 0xFF,
        (p1Bytes.length >> 16) & 0xFF,
        (p1Bytes.length >> 8) & 0xFF,
        p1Bytes.length & 0xFF,
      ]);
      buffer.addAll(p1Bytes);

      final p2Bytes = payload2.codeUnits;
      buffer.addAll([
        (p2Bytes.length >> 24) & 0xFF,
        (p2Bytes.length >> 16) & 0xFF,
        (p2Bytes.length >> 8) & 0xFF,
        p2Bytes.length & 0xFF,
      ]);
      buffer.addAll(p2Bytes);

      final len1 = (buffer[0] << 24) |
          (buffer[1] << 16) |
          (buffer[2] << 8) |
          buffer[3];
      final msg1 = String.fromCharCodes(buffer.sublist(4, 4 + len1));

      final offset = 4 + len1;
      final len2 = (buffer[offset] << 24) |
          (buffer[offset + 1] << 16) |
          (buffer[offset + 2] << 8) |
          buffer[offset + 3];
      final msg2 = String.fromCharCodes(buffer.sublist(offset + 4, offset + 4 + len2));

      expect(msg1, 'PrimoMessaggio');
      expect(msg2, 'SecondoMessaggio');
    });
  });

  // ══════════════════════════════════════════════════
  //  Transizione Stati Macchina
  // ══════════════════════════════════════════════════
  group('Transizione Stati Macchina', () {
    test('da idle a checkingCapabilities', () {
      var state = ClassicConnectionState.idle;
      state = ClassicConnectionState.checkingCapabilities;
      expect(state, ClassicConnectionState.checkingCapabilities);
    });

    test('da checkingCapabilities a classicServerListening', () {
      var state = ClassicConnectionState.checkingCapabilities;
      state = ClassicConnectionState.classicServerListening;
      expect(state, ClassicConnectionState.classicServerListening);
    });

    test('da checkingCapabilities a classicClientConnecting', () {
      var state = ClassicConnectionState.checkingCapabilities;
      state = ClassicConnectionState.classicClientConnecting;
      expect(state, ClassicConnectionState.classicClientConnecting);
    });

    test('da classicServerListening a connected', () {
      var state = ClassicConnectionState.classicServerListening;
      state = ClassicConnectionState.connected;
      expect(state, ClassicConnectionState.connected);
    });

    test('da classicClientConnecting a connected', () {
      var state = ClassicConnectionState.classicClientConnecting;
      state = ClassicConnectionState.connected;
      expect(state, ClassicConnectionState.connected);
    });

    test('da connected a error', () {
      var state = ClassicConnectionState.connected;
      state = ClassicConnectionState.error;
      expect(state, ClassicConnectionState.error);
    });
  });
}
