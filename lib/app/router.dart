import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_provider.dart';
import '../features/auth/login_page.dart';
import '../features/classes/my_group_page.dart';
import '../features/classes/group_management_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/students/students_page.dart';
import '../shared/models/student_model.dart';
import '../features/students/student_detail_page.dart';
import '../features/meetings/attendance_meetings_page.dart';
import '../features/meetings/attendance_page.dart';
import '../features/meetings/attendance_grid_page.dart';
import '../features/planning/planning_page.dart';
import '../features/documents/documents_page.dart';
import '../features/settings/settings_page.dart';
import '../features/contact_notes/contact_notes_page.dart';

import '../features/settings/licenses_page.dart';
import '../features/settings/privacy.dart';
import '../features/onboarding/presentation/screens/onboarding_page.dart';
import '../core/storage/local_database.dart';
import '../features/settings/backup_page.dart';
import '../features/settings/delete_data_page.dart';
import '../features/documents/document_detail_page.dart';
import '../features/students/allergies_page.dart';
import '../features/students/autonomous_exits_page.dart';
import '../features/phone_verification/verify_number_page.dart';
import '../features/update/update_page.dart';
import '../features/data_share/data_share_selection_page.dart';
import '../features/data_share/data_share_send_page.dart';
import '../features/data_share/data_share_receive_page.dart';
import '../screens/settings_association_screen.dart';
import '../features/catechesi/catechesi_page.dart';
import '../features/catechesi/catechesi_edit_page.dart';
import '../features/catechesi/catechesi_detail_page.dart';
import '../shared/models/catechesi_model.dart';

// ══════════════════════════════════════════════════════════════════════════════
// router.dart — CatechHub (configurazione navigazione)
//
// Configurazione centralizzata della navigazione dell'applicazione
// CatechHub utilizzando GoRouter v17 con Riverpod.
//
// Questo file definisce:
// 1. Il redirect di autenticazione (login guard)
// 2. Tutte le route dell'applicazione
// 3. Il meccanismo di refresh automatico quando lo stato auth cambia
//
// ARCHITETTURA NAVIGAZIONE:
//   GoRouter è un router dichiarativo per Flutter che gestisce:
//   - Navigazione basata su URL (path-based routing)
//   - Redirect automatici (auth guard)
//   - Refresh reattivo quando lo stato Riverpod cambia
//   - Supporto per parametri extra (oggetti Dart complessi)
//
//   Il router è definito come Riverpod Provider (appRouterProvider)
//   per garantire che:
//   - Il router venga creato una sola volta (singleton)
//   - Il redirect possa accedere a authStateProvider tramite ref
//   - Le risorse vengano rilasciate correttamente al dispose
//
// ROUTE DELL'APPLICAZIONE:
//   - /login: schermata di sblocco (PIN/biometrico)
//   - /: dashboard principale
//   - /students: anagrafica studenti
//   - /student-detail: dettaglio singolo studente
//   - /attendance-meetings: selezione incontro per presenze
//   - /attendance: registrazione presenze
//   - /planning: programmazione incontri
//   - /documents: gestione documenti
//   - /document-detail: dettaglio documento
//   - /settings: impostazioni generali
      //   - /privacy-security: impostazioni privacy e sicurezza
      //   - /delete-data: cancellazione dati
      //   - /backup: backup e ripristino dati
      //   - /contact-notes: note di contatto genitori
//   - /my-group: gruppo del catechista
//   - /group-management: gestione gruppi
//   - /allergies: vista allergie studenti
//   - /autonomous-exits: uscite autonome studenti
//   - /verify-number: verifica numero telefono
//   - /updates: aggiornamenti app
//   - /data-share: condivisione dati (QR)
//   - /settings/association: pairing Nearby Connections
//   - /catechesi: libreria contenuti catechetici
//   - /catechesi/edit: modifica/creazione catechesi
//   - /catechesi/detail: dettaglio catechesi
//
// CONTESTO PROGETTO:
//   CatechHub è un'app privacy-first per la gestione di registri di
//   catechismo. La navigazione è protetta da auth guard che richiede
//   autenticazione (PIN o biometrico) prima di accedere a qualsiasi
//   route protetta. Il redirect gestisce automaticamente i transiti
//   tra login e area autenticata.
// ══════════════════════════════════════════════════════════════════════════════

/// ═══════════════════════════════════════════════════════════════════════════════
/// NOTIFIER PER IL REFRESH DEL ROUTER BASATO SULLAUTENTICAZIONE
/// ═══════════════════════════════════════════════════════════════════════════════
///
/// Ottimizzato per GoRouter v17: implementa ChangeNotifier (Listenable)
/// per notificare a GoRouter i cambiamenti dello stato di autenticazione.
///
/// MECCANISMO:
///   1. Ascolta authStateProvider tramite Riverpod ref.listen()
///   2. Ad ogni cambio di stato (loading → data, data → error, ecc.),
///      chiama notifyListeners()
///   3. GoRouter, configurato con refreshListenable: questo notifier,
///      riceve la notifica e ri-evalua il redirect
///   4. Il redirect (sotto) determina se navigare a /login o rimanere
///      sulla route corrente
///
/// PERCHÉ È NECESSARIO:
///   GoRouter non monitora automaticamente i provider Riverpod.
///   Senza questo notifier, il redirect non verrebbe re-evaluato
///   quando l'utente si autentica o la sessione scade.
/// ═══════════════════════════════════════════════════════════════════════════════
class _AuthStateNotifier extends ChangeNotifier {
  final Ref _ref;
  ProviderSubscription? _subscription;

  _AuthStateNotifier(this._ref) {
    // Ascolta i cambiamenti di authStateProvider.
    // Ad ogni cambio (prev → next), notifica GoRouter.
    _subscription = _ref.listen(authStateProvider, (prev, next) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }
}

/// ═══════════════════════════════════════════════════════════════════════════════
/// PROVIDER DEL ROUTER GLOBALE DELL'APPLICAZIONE
/// ═══════════════════════════════════════════════════════════════════════════════
///
/// GoRouter configurato come Riverpod Provider per garantire:
/// - Singleton: il router viene creato una sola volta per l'intera app
/// - Dependency injection: il redirect può accedere a ref.read(authStateProvider)
/// - Lifecycle: ref.onDispose() rilascia il _AuthStateNotifier
///
/// La configurazione include:
/// - initialLocation: '/' (dashboard)
/// - refreshListenable: _AuthStateNotifier (ascolta auth state)
/// - redirect: auth guard (login guard)
/// - routes: lista completa delle route dell'app
///
/// @return Istanza singleton di GoRouter
final appRouterProvider = Provider<GoRouter>((ref) {
  // Crea il notifier per il refresh del router basato sull'autenticazione
  final refreshNotifier = _AuthStateNotifier(ref);

  // Assicura il corretto smaltimento del notifier alla distruzione del provider.
  // Senza questo, il notifier continuerebbe ad ascoltare authStateProvider
  // anche dopo che il provider è stato distrutto, causando memory leak.
  ref.onDispose(() => refreshNotifier.dispose());

  return GoRouter(
    // Route iniziale: dashboard principale
    initialLocation: '/',

    // Collega il ChangeNotifier al router per il refresh reattivo.
    // Ad ogni cambio di auth state, GoRouter ri-evalua il redirect.
    refreshListenable: refreshNotifier,

    // ─────────────────────────────────────────────────────────────────────
    // REDIRECT DI AUTENTICAZIONE (AUTH GUARD)
    //
    // Determina se l'utente deve essere reindirizzato a /login o se può
    // accedere alla route richiesta. Viene eseguito ad ogni navigazione
    // e ad ogni cambio di auth state.
    //
    // Logica:
    //   - Loading: non fare nulla (lascia che il router mostri la route corrente)
    //   - Error: reindirizza a /login (a meno che non sia già su /login)
    //   - Data (user != null): utente autenticato, consenti navigazione
    //   - Data (user == null): utente non autenticato, reindirizza a /login
    //   - Data (user != null, path == /login): reindirizza a / (dashboard)
    //
    // NOTA: state.matchedLocation restituisce solo il path senza query
    // parameters, garantendo che il confronto sia preciso.
    // ─────────────────────────────────────────────────────────────────────
    redirect: (BuildContext context, GoRouterState state) {
      final location = state.matchedLocation;

      // ─────────────────────────────────────────────────────────────────────
      // ONBOARDING GUARD - prima visita assoluta
      //
      // Se l'utente non ha ancora completato l'onboarding (primo avvio),
      // viene reindirizzato alla schermata di benvenuto.
      //
      // L'onboarding spiega il funzionamento dell'app e richiede i
      // permessi uno per uno (notifiche, fotocamera, Bluetooth).
      // ─────────────────────────────────────────────────────────────────────
      if (location != '/onboarding') {
        try {
          final onboardingDone = LocalDatabase.auth()
              .get('onboarding_completed', defaultValue: false) as bool;
          if (!onboardingDone) return '/onboarding';
        } catch (_) {
          return '/onboarding';
        }
      }

      // ─────────────────────────────────────────────────────────────────────
      // REDIRECT DI AUTENTICAZIONE (AUTH GUARD)
      //
      // Determina se l'utente deve essere reindirizzato a /login o se può
      // accedere alla route richiesta. Viene eseguito ad ogni navigazione
      // e ad ogni cambio di auth state.
      //
      // Logica:
      //   - Se siamo sulla pagina di onboarding: salta l'auth guard
      //     (l'utente deve prima completare l'onboarding, poi verrà
      //     reindirizzato a /login dall'onboarding stesso)
      //   - Loading: non fare nulla (lascia che il router mostri la route corrente)
      //   - Error: reindirizza a /login (a meno che non sia già su /login)
      //   - Data (user != null): utente autenticato, consenti navigazione
      //   - Data (user == null): utente non autenticato, reindirizza a /login
      //   - Data (user != null, path == /login): reindirizza a / (dashboard)
      //
      // NOTA: state.matchedLocation restituisce solo il path senza query
      // parameters, garantendo che il confronto sia preciso.
      // ─────────────────────────────────────────────────────────────────────
      if (location == '/onboarding') return null;

      final authState = ref.read(authStateProvider);
      final isLoginPath = location == '/login';

      return authState.when(
        loading: () => null,
        error: (_, __) => isLoginPath ? null : '/login',
        data: (user) {
          if (user == null && !isLoginPath) return '/login';
          if (user != null && isLoginPath) return '/';
          return null;
        },
      );
    },

    // ─────────────────────────────────────────────────────────────────────
    // ROUTE DELL'APPLICAZIONE
    //
    // Ogni route è definita come GoRoute con path univoco e builder.
    // Alcune route utilizzano state.extra per passare parametri complessi
    // (oggetti Dart) che non possono essere codificati nell'URL.
    //
    // Le route sono organizzate per dominio funzionale:
    // - Auth: login, autenticazione
    // - Dashboard: schermata principale
    // - Students: anagrafica e dettaglio studenti
    // - Attendance: presenze agli incontri
    // - Planning: programmazione incontri
    // - Documents: gestione documenti
    // - Settings: impostazioni e privacy
    // - Sync: sincronizzazione Bluetooth
    // - Catechesi: contenuti catechetici
    // ─────────────────────────────────────────────────────────────────────
    routes: [
      // ═══════════════════════════════════════════════════════════════════
      // ONBOARDING - Prima configurazione (solo al primo avvio)
      // ═══════════════════════════════════════════════════════════════════
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingPage()),

      // ═══════════════════════════════════════════════════════════════════
      // AUTH - Schermata di sblocco (PIN/biometrico)
      // ═══════════════════════════════════════════════════════════════════
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),

      // ═══════════════════════════════════════════════════════════════════
      // DASHBOARD - Schermata principale
      // ═══════════════════════════════════════════════════════════════════
      GoRoute(path: '/', builder: (context, state) => const DashboardPage()),

      // ═══════════════════════════════════════════════════════════════════
      // STUDENTS - Anagrafica studenti
      // ═══════════════════════════════════════════════════════════════════

      /// Lista completa degli studenti con ricerca e filtri
      GoRoute(
        path: '/students',
        builder: (context, state) => const StudentsPage(),
      ),

      /// Dettaglio singolo studente (anagrafica, presenze, note, allegati).
      /// I dati dello studente vengono passati tramite state.extra.
      GoRoute(
        path: '/student-detail',
        builder: (context, state) => const StudentDetailPage(),
      ),

      // ═══════════════════════════════════════════════════════════════════
      // ATTENDANCE FLOW - Registrazione presenze
      // ═══════════════════════════════════════════════════════════════════

      /// Selezione dell'incontro per cui registrare le presenze.
      /// Mostra la lista degli incontri programmati.
      GoRoute(
        path: '/attendance-meetings',
        builder: (context, state) => const AttendanceMeetingsPage(),
      ),

      /// Registrazione presenze per un incontro specifico.
      /// L'oggetto meeting viene passato tramite state.extra.
      /// Permette di segnare presenti/assenti ogni studente del gruppo.
      GoRoute(
        path: '/attendance',
        builder: (context, state) {
          final meeting = state.extra;
          return AttendancePage(meeting: meeting);
        },
      ),

      /// Griglia riepilogativa presenze: tutti gli studenti vs tutti gli
      /// incontri passati, con indicatori P/A per una visione d'insieme.
      GoRoute(
        path: '/attendance-grid',
        builder: (context, state) => const AttendanceGridPage(),
      ),

      // ═══════════════════════════════════════════════════════════════════
      // PLANNING - Programmazione incontri
      // ═══════════════════════════════════════════════════════════════════

      /// Calendario degli incontri di catechismo con titolo, attività e note.
      /// Distingue tra incontri studenti e riunioni catechisti.
      GoRoute(
        path: '/planning',
        builder: (context, state) => const PlanningPage(),
      ),

      // ═══════════════════════════════════════════════════════════════════
      // DOCUMENTS - Gestione documenti
      // ═══════════════════════════════════════════════════════════════════

      /// Lista dei documenti con ciclo vita (creazione, consegna, restituzione).
      GoRoute(
        path: '/documents',
        builder: (context, state) => const DocumentsPage(),
      ),

      /// Dettaglio documento con stato di consegna per ogni studente.
      /// I dati vengono passati tramite state.extra come mappa.
      GoRoute(
        path: '/document-detail',
        builder: (context, state) {
          final extraData = state.extra is Map<String, dynamic> ? state.extra as Map<String, dynamic> : const <String, dynamic>{};

          return DocumentDetailPage(
            document: extraData['document'] as Map<String, dynamic>? ?? {},
            students: extraData['students'] as List<Student>? ?? [],
          );
        },
      ),

      // ═══════════════════════════════════════════════════════════════════
      // SETTINGS - Impostazioni e sicurezza
      // ═══════════════════════════════════════════════════════════════════

      /// Impostazioni generali dell'app (notifiche, aggiornamenti, feedback).
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),

      /// Licenze open source delle dipendenze utilizzate.
      GoRoute(
        path: '/settings/licenses',
        builder: (context, state) => const LicensesPage(),
      ),

      /// Impostazioni privacy e sicurezza:
      /// - FLAG_SECURE (screenshot)
      /// - Timeout sessione
      /// - Privacy settings
      /// - Blocco automatico
      GoRoute(
        path: '/privacy-security',
        builder: (context, state) => const PrivacySecurityPage(),
      ),

      /// Pagina di cancellazione dati: reset completo dell'app con
      /// eliminazione di tutti i Box Hive e dei dati sensibili.
      GoRoute(
        path: '/delete-data',
        builder: (context, state) => const DeleteDataPage(),
      ),

      /// Pagina di backup e ripristino dati: esporta/importa backup cifrati.
      GoRoute(
        path: '/backup',
        builder: (context, state) => const BackupPage(),
      ),

      // ═══════════════════════════════════════════════════════════════════
      // CONTACT NOTES - Note di contatto genitori
      // ═══════════════════════════════════════════════════════════════════

      /// Registro delle comunicazioni con i genitori (incontro, WhatsApp,
      /// telefono) con data, ora e note.
      GoRoute(
        path: '/contact-notes',
        builder: (context, state) => const ContactNotesPage(),
      ),

      // ═══════════════════════════════════════════════════════════════════
      // CLASSES - Gestione gruppi di catechismo
      // ═══════════════════════════════════════════════════════════════════

      /// Pagina del gruppo assegnato al catechista corrente.
      /// Mostra la lista degli studenti del gruppo.
      GoRoute(
        path: '/my-group',
        builder: (context, state) => const MyGroupPage(),
      ),

      /// Gestione dei gruppi di catechismo: creazione, modifica,
      /// assegnazione catechisti e studenti.
      GoRoute(
        path: '/group-management',
        builder: (context, state) => const GroupManagementPage(),
      ),

      // ═══════════════════════════════════════════════════════════════════
      // ALLERGIES & EXITS - Dati sanitari e autorizzazioni
      // ═══════════════════════════════════════════════════════════════════

      /// Vista dedicata alle allergie degli studenti.
      /// Informazione critica per la sicurezza alimentare durante gli
      /// incontri con pasti o merende.
      GoRoute(
        path: '/allergies',
        builder: (context, state) => const AllergiesPage(),
      ),

      /// Gestione delle autorizzazioni per uscite autonome degli studenti.
      /// Registra quali studenti possono uscire senza accompagnamento.
      GoRoute(
        path: '/autonomous-exits',
        builder: (context, state) => const AutonomousExitsPage(),
      ),

      // ═══════════════════════════════════════════════════════════════════
      // PHONE VERIFICATION - Verifica contatti
      // ═══════════════════════════════════════════════════════════════════

      /// Verifica della completezza dei numeri di telefono dei genitori.
      GoRoute(
        path: '/verify-number',
        builder: (context, state) => const VerifyNumberPage(),
      ),

      // ═══════════════════════════════════════════════════════════════════
      // UPDATES - Aggiornamenti applicazione
      // ═══════════════════════════════════════════════════════════════════

      /// Pagina di gestione aggiornamenti con download APK.
      GoRoute(
        path: '/updates',
        builder: (context, state) => const UpdatePage(),
      ),

      // ═══════════════════════════════════════════════════════════════════
      // DATA SHARE - Condivisione dati
      // ═══════════════════════════════════════════════════════════════════

      /// Selezione modalità condivisione: invio o ricezione dati.
      /// Supporta QR code e Bluetooth RFCOMM.
      GoRoute(
        path: '/data-share',
        builder: (context, state) => const DataShareSelectionPage(),
      ),

      /// Invio dati: genera QR code o avvia trasmissione Bluetooth.
      GoRoute(
        path: '/data-share/send',
        builder: (context, state) => const DataShareSendPage(),
      ),

      /// Ricezione dati: scansiona QR code o attende connessione Bluetooth.
      GoRoute(
        path: '/data-share/receive',
        builder: (context, state) => const DataShareReceivePage(),
      ),

      // ═══════════════════════════════════════════════════════════════════
      // ASSOCIATION - Associazione dispositivi (QR + Nearby Connections)
      // ═══════════════════════════════════════════════════════════════════

      /// Schermata di associazione dispositivi tramite QR Code e
      /// sincronizzazione tramite Google Nearby Connections.
      GoRoute(
        path: '/settings/association',
        builder: (context, state) => const SettingsAssociationScreen(),
      ),

      // ═══════════════════════════════════════════════════════════════════
      // CATECHESI - Libreria contenuti catechetici
      // ═══════════════════════════════════════════════════════════════════

      /// Lista dei contenuti catechetici con tag, riferimenti biblici e link.
      GoRoute(

        path: '/catechesi',
        builder: (context, state) => const CatechesiPage(),
      ),

      /// Creazione/modifica di un contenuto catechetico.
      /// Se state.extra contiene un oggetto Catechesi, è una modifica;
      /// altrimenti è una creazione nuova.
      GoRoute(
        path: '/catechesi/edit',
        builder: (context, state) {
          final extra = state.extra is Map<String, dynamic> ? state.extra as Map<String, dynamic> : const <String, dynamic>{};
          final catechesi = extra['catechesi'] as Catechesi?;
          return CatechesiEditPage(existing: catechesi);
        },
      ),

      /// Dettaglio completo di un contenuto catechetico con foto,
      /// riferimenti biblici e link esterni.
      GoRoute(
        path: '/catechesi/detail',
        builder: (context, state) {
          final extra = state.extra is Map<String, dynamic> ? state.extra as Map<String, dynamic> : const <String, dynamic>{};
          final catechesi = extra['catechesi'] as Catechesi?;
          return CatechesiDetailPage(catechesi: catechesi!);
        },
      ),
    ],
  );
});
