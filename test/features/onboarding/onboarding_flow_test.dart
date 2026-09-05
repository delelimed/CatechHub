// ============================================================================
// TEST: OnboardingPage — flusso a 2 schermate
// Copre: permessi contestuali, selezione modalità operativa e persistenza
// (ruolo, app_mode, setup_mode, configurazione parrocchiale).
//
// NOTA SUL BACKEND MEMORIA: i box Hive vengono aperti con StorageBackendMemory
// (scritture sincrone in memoria, nessun I/O su disco). Le scritture Hive
// programmano altrimenti timer/operazioni asincrone reali che, nel FakeAsync
// di testWidgets, non completano e bloccano il teardown del test ("did not
// complete"). Con il backend in memoria ogni put() completa in un microtask
// e il flusso di onboarding (che esegue diverse put sequenziali) può essere
// guidato dal semplice pumpAndSettle.
// ============================================================================
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/features/onboarding/presentation/screens/onboarding_page.dart';
import 'package:CatechHub/features/responsabile/parish_config_repository.dart';
import 'package:CatechHub/shared/models/user_role.dart';

void main() {
  setUp(() async {
    Hive.init(Directory.systemTemp.path);
    await Hive.openBox(
      LocalDatabase.authBox,
      bytes: Uint8List.fromList([]),
    );
    await Hive.openBox(
      LocalDatabase.parishConfigBox,
      bytes: Uint8List.fromList([]),
    );
  });

  tearDown(() async {
    await Hive.close();
  });

  GoRouter buildRouter() {
    return GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingPage()),
        GoRoute(
          path: '/login',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('LOGIN_DEST'))),
        ),
        GoRoute(
          path: '/onboarding-sync',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('SYNC_DEST'))),
        ),
      ],
    );
  }

  Future<void> pumpOnboarding(WidgetTester tester) async {
    // Viewport alto per evitare che card e pulsanti finiscano fuori schermo
    // (il default 800x600 taglierebbe la selezione della modalità).
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: buildRouter())),
    );
    await tester.pumpAndSettle();
  }

  group('OnboardingPage', () {
    testWidgets('mostra prima i permessi contestuali (nessun OS prompt)', (
      tester,
    ) async {
      await pumpOnboarding(tester);

      expect(find.text('Prima di iniziare'), findsOneWidget);
      expect(find.text('Notifiche'), findsOneWidget);
      expect(find.text('Connessione locale (P2P)'), findsOneWidget);
      expect(find.text('Fotocamera'), findsOneWidget);
      expect(find.text('Attiva le notifiche'), findsOneWidget);
      expect(find.text('Attiva la connessione P2P'), findsOneWidget);
      expect(find.text('Attiva la fotocamera'), findsOneWidget);
    });

    testWidgets('Salta porta alla selezione della modalità', (tester) async {
      await pumpOnboarding(tester);

      await tester.tap(find.text('Salta'));
      await tester.pumpAndSettle();

      expect(find.text('Modalità Responsabile Catechistico'), findsOneWidget);
      expect(
        find.text('Modalità Normale (Senza Responsabile)'),
        findsOneWidget,
      );
      expect(find.text('Associa a Classe Esistente'), findsOneWidget);
    });

    testWidgets('modalità Normale salva ruolo, app_mode e naviga a /login', (
      tester,
    ) async {
      await pumpOnboarding(tester);

      await tester.tap(find.text('Salta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modalità Normale (Senza Responsabile)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conferma modalità'));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN_DEST'), findsOneWidget);
      expect(LocalDatabase.auth().get('app_mode'), 'NORMAL');
      expect(LocalDatabase.auth().get('setup_mode'), 'create');
      expect(UserRole.current(), UserRole.catechista);
      expect(LocalDatabase.auth().get('onboarding_completed'), true);
      expect(
        ParishConfigRepository().getConfig().isResponsabileModeActive,
        false,
      );
    });

    testWidgets('modalità Responsabile attiva la modalità e naviga a /login', (
      tester,
    ) async {
      await pumpOnboarding(tester);

      await tester.tap(find.text('Salta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modalità Responsabile Catechistico'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conferma modalità'));
      await tester.pumpAndSettle();

      // STEP 2: in Modalità Responsabile si chiede il nome della parrocchia.
      expect(find.text('La tua parrocchia'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).first,
        'Parrocchia San Testo',
      );
      await tester.tap(find.text('Continua'));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN_DEST'), findsOneWidget);
      expect(LocalDatabase.auth().get('app_mode'), 'RESPONSABILE');
      expect(LocalDatabase.auth().get('setup_mode'), 'responsabile');
      expect(UserRole.current(), UserRole.responsabile);
      expect(LocalDatabase.auth().get('onboarding_completed'), true);
      expect(
        ParishConfigRepository().getConfig().isResponsabileModeActive,
        true,
      );
      expect(
        ParishConfigRepository().getConfig().nomeParrocchia,
        'Parrocchia San Testo',
      );
    });

    testWidgets(
      'Associa a Classe Esistente naviga a /onboarding-sync senza form',
      (tester) async {
        await pumpOnboarding(tester);

        await tester.tap(find.text('Salta'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Associa a Classe Esistente'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Conferma modalità'));
        await tester.pumpAndSettle();

        expect(find.text('SYNC_DEST'), findsOneWidget);
        expect(LocalDatabase.auth().get('app_mode'), 'REPLICATED_PEER');
        expect(LocalDatabase.auth().get('setup_mode'), 'join');
        expect(UserRole.current(), UserRole.catechista);
        expect(LocalDatabase.auth().get('onboarding_completed'), true);
        // Nessun form anagrafico richiesto
        expect(LocalDatabase.auth().get('first_name'), isNot(isA<String>()));
      },
    );

    testWidgets('Conferma senza selezione mostra un errore', (tester) async {
      await pumpOnboarding(tester);

      await tester.tap(find.text('Salta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continua'));
      await tester.pumpAndSettle();

      expect(
        find.text('Seleziona una modalità per continuare.'),
        findsOneWidget,
      );
      expect(LocalDatabase.auth().get('onboarding_completed'), isNot(true));
    });
  });
}