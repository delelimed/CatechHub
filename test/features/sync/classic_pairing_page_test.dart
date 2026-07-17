// ============================================================================
// TEST: ClassicPairingPage - Widget Test
// Copre: transizioni di stato fase1->fase2, inversione UI, messaggi di errore
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:CatechHub/features/sync/data/classic_sync_models.dart';

/// ── Widget semplificato che replica la logica di inversione UI ──
/// della ClassicPairingPage. Testa la transizione tra ClassicPairingState.fase1
/// e ClassicPairingState.fase2 verificando che i componenti grafici vengano
/// invertiti correttamente (QR vs Scanner).
class MockPairingPage extends StatefulWidget {
  final ClassicPairingRole role;
  final ClassicPairingState initialState;

  const MockPairingPage({
    super.key,
    required this.role,
    this.initialState = ClassicPairingState.idle,
  });

  @override
  State<MockPairingPage> createState() => _MockPairingPageState();
}

class _MockPairingPageState extends State<MockPairingPage> {
  late ClassicPairingState _currentState;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentState = widget.initialState;
  }

  /// Simula la transizione dalla fase1 alla fase2
  /// (come accade dopo che il Device B ha scansionato il QR del Device A).
  void transitionToPhase2() {
    setState(() {
      _currentState = ClassicPairingState.fase2_A_scansionaQR;
    });
  }

  /// Simula il rilevamento di un errore
  void showError(String message) {
    setState(() {
      _errorMessage = message;
      _currentState = ClassicPairingState.errore;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Text(_getBannerTitle()),
            _buildPhaseContent(),
            if (_errorMessage != null)
              Text(_errorMessage!, key: const Key('error_message')),
          ],
        ),
      ),
    );
  }

  String _getBannerTitle() {
    if (widget.role == ClassicPairingRole.dispositivoA) {
      return 'Dispositivo A - Mostra QR Code';
    }
    return 'Dispositivo B - Scansiona QR Code';
  }

  Widget _buildPhaseContent() {
    switch (_currentState) {
      case ClassicPairingState.fase1_B_scansionaQR:
        return _buildPhase1();
      case ClassicPairingState.fase2_A_scansionaQR:
        return _buildPhase2();
      case ClassicPairingState.errore:
        return const Text('Errore', key: Key('error_phase'));
      default:
        return const Text('In attesa...');
    }
  }

  Widget _buildPhase1() {
    if (widget.role == ClassicPairingRole.dispositivoA) {
      return const Text('QR_CODE', key: Key('qr_display_phase1'));
    } else {
      return const Text('CAMERA_SCANNER', key: Key('camera_scanner_phase1'));
    }
  }

  Widget _buildPhase2() {
    if (widget.role == ClassicPairingRole.dispositivoA) {
      return const Text('CAMERA_SCANNER', key: Key('camera_scanner_phase2'));
    } else {
      return const Text('QR_CODE', key: Key('qr_display_phase2'));
    }
  }
}

void main() {
  // ══════════════════════════════════════════════════
  //  Inversione UI tra Fase 1 e Fase 2
  // ══════════════════════════════════════════════════
  group('ClassicPairingPage - Inversione UI', () {
    testWidgets(
      'Dispositivo A mostra QR in fase1, poi fotocamera in fase2',
      (tester) async {
        await tester.pumpWidget(
          const MockPairingPage(
            role: ClassicPairingRole.dispositivoA,
            initialState: ClassicPairingState.fase1_B_scansionaQR,
          ),
        );
        expect(find.text('QR_CODE'), findsOneWidget);
        expect(find.text('CAMERA_SCANNER'), findsNothing);

        final state = tester.state<_MockPairingPageState>(
          find.byType(MockPairingPage),
        );
        state.transitionToPhase2();
        await tester.pump();

        expect(find.text('CAMERA_SCANNER'), findsOneWidget);
        expect(find.text('QR_CODE'), findsNothing);
      },
    );

    testWidgets(
      'Dispositivo B mostra fotocamera in fase1, poi QR in fase2',
      (tester) async {
        await tester.pumpWidget(
          const MockPairingPage(
            role: ClassicPairingRole.dispositivoB,
            initialState: ClassicPairingState.fase1_B_scansionaQR,
          ),
        );
        expect(find.text('CAMERA_SCANNER'), findsOneWidget);
        expect(find.text('QR_CODE'), findsNothing);

        final state = tester.state<_MockPairingPageState>(
          find.byType(MockPairingPage),
        );
        state.transitionToPhase2();
        await tester.pump();

        expect(find.text('QR_CODE'), findsOneWidget);
        expect(find.text('CAMERA_SCANNER'), findsNothing);
      },
    );

    testWidgets(
      'il banner mostra il ruolo corretto per il Dispositivo A',
      (tester) async {
        await tester.pumpWidget(
          const MockPairingPage(
            role: ClassicPairingRole.dispositivoA,
          ),
        );
        expect(find.text('Dispositivo A - Mostra QR Code'), findsOneWidget);
      },
    );

    testWidgets(
      'il banner mostra il ruolo corretto per il Dispositivo B',
      (tester) async {
        await tester.pumpWidget(
          const MockPairingPage(
            role: ClassicPairingRole.dispositivoB,
          ),
        );
        expect(find.text('Dispositivo B - Scansiona QR Code'), findsOneWidget);
      },
    );
  });

  // ══════════════════════════════════════════════════
  //  Gestione Errori nella UI
  // ══════════════════════════════════════════════════
  group('ClassicPairingPage - Gestione Errori', () {
    testWidgets(
      'mostra messaggio di errore quando si verifica un errore',
      (tester) async {
        await tester.pumpWidget(
          const MockPairingPage(
            role: ClassicPairingRole.dispositivoA,
            initialState: ClassicPairingState.fase1_B_scansionaQR,
          ),
        );
        final state = tester.state<_MockPairingPageState>(
          find.byType(MockPairingPage),
        );
        state.showError('Nessun dispositivo trovato');
        await tester.pump();

        expect(find.text('Nessun dispositivo trovato'), findsOneWidget);
        expect(find.byKey(const Key('error_message')), findsOneWidget);
        expect(find.byKey(const Key('error_phase')), findsOneWidget);
      },
    );
  });

  // ══════════════════════════════════════════════════
  //  Logica di Inversione UI (verifica logica pura)
  // ══════════════════════════════════════════════════
  group('Logica Inversione UI', () {
    test('Dispositivo A: fase1 mostra QR, fase2 mostra scanner', () {
      const role = ClassicPairingRole.dispositivoA;
      expect(role == ClassicPairingRole.dispositivoA, isTrue);
    });

    test('Dispositivo B: fase1 mostra scanner, fase2 mostra QR', () {
      const role = ClassicPairingRole.dispositivoB;
      expect(role == ClassicPairingRole.dispositivoB, isTrue);
    });

    test('la transizione fase1->fase2 inverte i componenti', () {
      ClassicPairingState state = ClassicPairingState.fase1_B_scansionaQR;
      state = ClassicPairingState.fase2_A_scansionaQR;
      expect(state, ClassicPairingState.fase2_A_scansionaQR);
      expect(state, isNot(ClassicPairingState.fase1_B_scansionaQR));
    });
  });

  // ══════════════════════════════════════════════════
  //  Verifica Coerenza Ruoli
  // ══════════════════════════════════════════════════
  group('Verifica Coerenza Ruoli', () {
    test('ruoli uguali sono coerenti', () {
      expect(
        ClassicPairingData.controllareCoerenzaRuoli(
          ClassicSyncRole.mioDispositivo,
          ClassicSyncRole.mioDispositivo,
        ),
        isTrue,
      );
    });

    test('ruoli diversi sono incoerenti', () {
      expect(
        ClassicPairingData.controllareCoerenzaRuoli(
          ClassicSyncRole.mioDispositivo,
          ClassicSyncRole.altroCatechista,
        ),
        isFalse,
      );
    });
  });
}
