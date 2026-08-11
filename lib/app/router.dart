import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_provider.dart';
import '../core/auth/auth_service.dart';
import '../features/auth/login_page.dart';
import '../features/classes/my_group_page.dart';
import '../features/classes/group_management_page.dart';
import '../features/classes/view_groups_page.dart';
import '../features/classes/class_selection_page.dart';
import '../features/classes/class_switcher_page.dart';
import '../features/classes/class_copy_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/dashboard/statistics_page.dart';
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
import '../features/contact_notes/avvisi_page.dart' show AvvisiPage;

import '../features/settings/licenses_page.dart';
import '../features/settings/changelog_page.dart';
import '../features/settings/commits_page.dart';
import '../features/settings/commit_detail_page.dart';
import '../features/settings/release_detail_page.dart';
import '../features/settings/privacy.dart';
import '../features/onboarding/presentation/screens/onboarding_page.dart';
import '../features/onboarding/presentation/screens/onboarding_sync_page.dart';
import '../features/onboarding/presentation/screens/onboarding_classes_page.dart';
import '../core/storage/local_database.dart';
import '../features/settings/backup_page.dart';
import '../features/settings/delete_data_page.dart';
import '../features/settings/pdf_report_page.dart';
import '../features/documents/document_detail_page.dart';
import '../features/students/allergies_page.dart';
import '../features/students/autonomous_exits_page.dart';
import '../features/phone_verification/verify_number_page.dart';
import '../features/update/update_page.dart';
import '../features/data_share/data_share_selection_page.dart';
import '../features/data_share/data_share_send_page.dart';
import '../features/data_share/data_share_receive_page.dart';
import '../features/sync/screens/approval_center_page.dart';
import '../features/sync/screens/settings_association_screen.dart';
import '../features/sync/screens/associate_device_screen.dart';
import '../features/sync/screens/sync_log_page.dart';
import '../features/sync/screens/conflict_resolution_page.dart';
import '../features/catechesi/catechesi_page.dart';
import '../features/catechesi/catechesi_edit_page.dart';
import '../features/catechesi/catechesi_detail_page.dart';
import '../shared/models/catechesi_model.dart';
import '../features/responsabile/responsabile_dashboard_page.dart';
import '../features/responsabile/responsabile_admin_page.dart';
import '../features/responsabile/audit_log_page.dart';
import '../features/responsabile/consensi_page.dart';
import '../features/responsabile/parish_network_page.dart';
import '../features/responsabile/import_ragazzi/import_ragazzi_page.dart';
import '../features/archive/pages/historical_archive_page.dart';
import '../features/substitutes/substitute_center_page.dart';
import '../features/substitutes/create_substitute_delegation_page.dart';
import '../features/substitutes/scan_substitute_delegation_page.dart';
import '../features/substitutes/substitute_register_page.dart';
import '../shared/models/user_role.dart';

/// Restituisce gli ID delle classi a cui appartiene il catechista locale.
///
/// Centrale per il redirect: evita di duplicare la logica di lettura del box
/// `classes` in più punti e rende coerente il trattamento di `current_class_id`
/// (che viene considerato valido SOLO se appartiene ancora al catechista).
///
/// Include anche le classi oggetto di una «supplenza temporanea» attiva in cui
/// il catechista locale è il Supplente: la delega rende temporaneamente
/// visibili classi che NON compaiono in `catechistIds` (isolamento dati).
List<String> _userClassIds() {
  final classesBox = LocalDatabase.classes();
  const localId = AuthService.localUserId;
  final ids = <String>{};
  for (final key in classesBox.keys) {
    final data = LocalDatabase.toStringDynamicMap(classesBox.get(key));
    final catechistIds = (data['catechistIds'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    if (catechistIds.contains(localId)) ids.add(key.toString());
  }

  // Classi in supplenza temporanea (Supplente locale): la delega deve essere
  // ancora visibile (attiva, o scaduta ma con dati non ancora acquisiti).
  try {
    final catechistId = AuthService.getCatechistId();
    final now = DateTime.now().toUtc();
    final delegationsBox = LocalDatabase.substituteDelegations();
    for (final key in delegationsBox.keys) {
      final data = LocalDatabase.toStringDynamicMap(delegationsBox.get(key));
      final substituteCatechistId = data['substituteCatechistId']?.toString();
      if (substituteCatechistId != catechistId) continue;
      final status = data['status']?.toString() ?? 'active';
      if (status == 'revoked' || status == 'completed') continue;
      final validFrom = DateTime.tryParse(data['validFrom']?.toString() ?? '');
      final validUntil = DateTime.tryParse(data['validUntil']?.toString() ?? '');
      if (validFrom != null && validUntil != null) {
        final active = !now.isBefore(validFrom) && !now.isAfter(validUntil);
        final expired = now.isAfter(validUntil) && data['dataCollected'] != true;
        if (active || (status == 'expired' && expired)) {
          final classId = data['classId']?.toString();
          if (classId != null && classId.isNotEmpty) ids.add(classId);
        }
      }
    }
  } catch (_) {}

  return ids.toList();
}

/// True se la route corrente appartiene alla gestione parrocchiale del
/// Responsabile Catechistico. Queste route NON richiedono una classe
/// selezionata (gestione parrocchia-wide).
bool _isParrocchiaRoute(String location) =>
    location.startsWith('/parrocchia');

/// Legge `current_class_id` e lo considera valido solo se non è vuoto e punta
/// a una classe di cui l'utente fa ancora parte. Un id "stantio" (classe
/// eliminata o a cui si è usciti) viene ignorato come nessuna selezione.
String? _validatedCurrentClassId() {
  final raw = LocalDatabase.auth().get('current_class_id');
  if (raw is! String || raw.isEmpty) return null;
  return _userClassIds().contains(raw) ? raw : null;
}

/// True durante la fase "Associa a Classe Esistente": la modalità operativa è
/// REPLICATED_PEER e il profilo non è ancora configurato (verrà ricevuto via
/// P2P dal dispositivo mittente). In questo stato la schermata /onboarding-sync
/// è raggiungibile senza autenticazione.
bool _isJoinPending() {
  try {
    final box = LocalDatabase.auth();
    final mode = box.get('app_mode', defaultValue: 'NORMAL') as String;
    if (mode != 'REPLICATED_PEER') return false;
    return box.get('first_name') is! String;
  } catch (_) {
    return false;
  }
}

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
      if (location != '/onboarding' &&
          location != '/class-selection' &&
          location != '/onboarding-classes') {
        try {
          final onboardingDone =
              LocalDatabase.auth().get(
                    'onboarding_completed',
                    defaultValue: false,
                  )
                  as bool;
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
      if (location == '/onboarding' ||
          location == '/class-selection' ||
          location == '/onboarding-classes') {
        return null;
      }

      final authState = ref.read(authStateProvider);
      final isLoginPath = location == '/login';
      final isOnboardingSyncPath = location == '/onboarding-sync';

      return authState.when(
        loading: () => null,
        error: (_, _) => isLoginPath ? null : '/login',
        data: (user) {
          if (user == null) {
            // Fase "Associa a Classe Esistente": nessun form anagrafico, il
            // profilo viene ricevuto via P2P. Finché la configurazione non è
            // completata, /onboarding-sync è raggiungibile senza autenticazione.
            if (isOnboardingSyncPath && _isJoinPending()) return null;
            if (!isLoginPath) return '/login';
            return null;
          }

          // Responsabile Catechistico: la home è la dashboard parrocchiale.
          // Non passa mai dalla selezione classe né dalla gestione classi
          // dell'onboarding (gestione centralizzata in /parrocchia).
          if (UserRole.isResponsabile) {
            if (isLoginPath) return '/parrocchia';
            if (location == '/' ||
                location == '/class-selection' ||
                location == '/onboarding-classes') {
              return '/parrocchia';
            }
            return null;
          }

          // Se l'utente ha scelto "unisciti" durante l'onboarding e
          // non ha ancora classi, reindirizza all'associazione P2P.
          // Questo controllo vale per OGNI navigazione, non solo /login,
          // per impedire di lasciare l'onboarding senza essere in una classe.
          if (!isOnboardingSyncPath) {
            try {
              final setupMode =
                  LocalDatabase.auth().get('setup_mode', defaultValue: 'create');
              if (setupMode == 'join') {
                if (_userClassIds().isEmpty) {
                  return '/onboarding-sync';
                }
              }
            } catch (_) {}
          }
          if (isLoginPath) {
            // Dopo il login si chiede SEMPRE quale classe aprire, anche se
            // una classe è già salvata come corrente: la selezione viene
            // proposta a ogni avvio dell'app (richiesta esplicita).
            // La pagina /class-selection gestisce anche il caso in cui
            // l'utente non faccia parte di alcun gruppo (empty state con
            // "Crea nuovo gruppo").
            try {
              // Fase di onboarding multiclasse: finché non viene completata
              // dal catechista, il router lo mantiene sulla schermata dedicata
              // alla gestione delle classi (funziona anche senza classi).
              final classesStepDone =
                  LocalDatabase.auth().get(
                        'onboarding_classes_completed',
                        defaultValue: true,
                      )
                      as bool;
              if (!classesStepDone) {
                return '/onboarding-classes';
              }
              return '/class-selection';
            } catch (_) {}
            return '/class-selection';
          }
          // Se l'utente è autenticato ma non ha una classe selezionata e non è su class-selection
          if (location != '/class-selection' &&
              location != '/onboarding-sync' &&
              location != '/onboarding-classes' &&
              !_isParrocchiaRoute(location)) {
            try {
              final userClassIds = _userClassIds();
              final hasClasses = userClassIds.isNotEmpty;
              final currentClassId = _validatedCurrentClassId();

              // Difesa in profondità: anche fuori da /login, se la gestione
              // classi dell'onboarding non è stata completata si torna alla
              // schermata dedicata (a meno di essere già su una route esclusa).
              final classesStepDone =
                  LocalDatabase.auth().get(
                        'onboarding_classes_completed',
                        defaultValue: true,
                      )
                      as bool;
              if (!classesStepDone) {
                return '/onboarding-classes';
              }

              if (hasClasses && (currentClassId == null || currentClassId.isEmpty)) {
                return '/class-selection';
              }
            } catch (_) {}
          }
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
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),

      // ═══════════════════════════════════════════════════════════════════
      // ONBOARDING SYNC - Sincronizzazione Bluetooth post-registrazione
      // ═══════════════════════════════════════════════════════════════════
      GoRoute(
        path: '/onboarding-sync',
        builder: (context, state) => const OnboardingSyncPage(),
      ),

      // ═══════════════════════════════════════════════════════════════════
      // ONBOARDING CLASSES - Gestione multiclasse durante l'onboarding
      // ═══════════════════════════════════════════════════════════════════
      GoRoute(
        path: '/onboarding-classes',
        builder: (context, state) => const OnboardingClassesPage(),
      ),

      // ═══════════════════════════════════════════════════════════════════
      // CLASS SELECTION - Selezione classe post-login
      // ══════════════════════════════════════════════════════════════════
      GoRoute(
        path: '/class-selection',
        builder: (context, state) => const ClassSelectionPage(),
      ),

      // ══════════════════════════════════════════════════════════════════
      // AUTH - Schermata di sblocco (PIN/biometrico)
      // ═══════════════════════════════════════════════════════════════════
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),

      // ═══════════════════════════════════════════════════════════════════
      // DASHBOARD - Schermata principale
      // ═══════════════════════════════════════════════════════════════════
      GoRoute(path: '/', builder: (context, state) => const DashboardPage()),

      // ═══════════════════════════════════════════════════════════════════
      // RESPONSABILE CATECHISTICO - Gestione parrocchiale
      // ═══════════════════════════════════════════════════════════════════

      /// Vista albero parrocchiale (Anno → Percorsi → Classi → Catechisti → Ragazzi)
      GoRoute(
        path: '/parrocchia',
        builder: (context, state) => const ResponsabileDashboardPage(),
      ),

      /// Hub amministrativo del Responsabile (classi, iscrizioni, logistica, allarmi).
      GoRoute(
        path: '/parrocchia/admin',
        builder: (context, state) => const ResponsabileAdminPage(),
      ),

      /// Registro Trattamenti GDPR (audit log).
      GoRoute(
        path: '/parrocchia/audit',
        builder: (context, state) => const AuditLogPage(),
      ),

      /// Gestione scheda di iscrizione firmata e contributi volontari.
      GoRoute(
        path: '/parrocchia/consensi',
        builder: (context, state) => const ConsensiPage(),
      ),

      /// Rete Catechistica Parrocchiale: riunioni/avvisi globali e titoli
      /// di classe (canale classe cifrato + QR handshake).
      GoRoute(
        path: '/parrocchia/rete',
        builder: (context, state) => const ParishNetworkPage(),
      ),

      /// Archivio Storico e Progresso dei Ragazzi: snapshot immutabili di
      /// ogni anno concluso + chiusura/promozione/archiviazione di fine anno.
      GoRoute(
        path: '/parrocchia/archivio',
        builder: (context, state) => const HistoricalArchivePage(),
      ),

      /// Importazione massiva anagrafica ragazzi da file .csv / .xlsx
      /// (riservata al profilo Responsabile).
      GoRoute(
        path: '/parrocchia/import-ragazzi',
        builder: (context, state) => const ImportRagazziPage(),
      ),

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
          final extraData = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : const <String, dynamic>{};

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

      /// Changelog delle versioni rilasciate.
      GoRoute(
        path: '/changelog',
        builder: (context, state) => const ChangelogPage(),
      ),

      /// Cronologia dei commit recenti dal repository GitHub.
      GoRoute(
        path: '/commits',
        builder: (context, state) => const CommitsPage(),
      ),

      /// Dettaglio di un singolo commit.
      GoRoute(
        path: '/commit-detail',
        builder: (context, state) {
          final commit = state.extra as Map<String, dynamic>? ?? {};
          return CommitDetailPage(commit: commit);
        },
      ),

      /// Dettaglio di una singola versione (release).
      GoRoute(
        path: '/release-detail',
        builder: (context, state) {
          final release = state.extra as Map<String, dynamic>? ?? {};
          return ReleaseDetailPage(release: release);
        },
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
      GoRoute(path: '/backup', builder: (context, state) => const BackupPage()),

      /// Pagina di esportazione report PDF (in sviluppo).
      GoRoute(
        path: '/pdf-report',
        builder: (context, state) => const PdfReportPage(),
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

      /// Gestione avvisi e messaggi standard per genitori.
      GoRoute(
        path: '/avvisi',
        builder: (context, state) => const AvvisiPage(),
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

      /// Visualizzazione di tutti i gruppi a cui appartiene il catechista.
      GoRoute(
        path: '/view-groups',
        builder: (context, state) => const ViewGroupsPage(),
      ),

      // ═══════════════════════════════════════════════════════════════════
      // STATISTICS - Statistiche del gruppo
      // ═══════════════════════════════════════════════════════════════════

      /// Pagina delle statistiche di presenza del gruppo.
      /// I dati (className, classId) vengono passati tramite state.extra.
      GoRoute(
        path: '/statistics',
        builder: (context, state) {
          final extra = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : <String, dynamic>{};
          return StatisticsPage(
            className: extra['className'] as String? ?? '',
            classId: extra['classId'] as String? ?? '',
          );
        },
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
      /// Supporta QR code e Nearby Connections.
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

      /// Schermata di sincronizzazione dispositivi associati.
      GoRoute(
        path: '/settings/association',
        builder: (context, state) => const SettingsAssociationScreen(),
      ),

      /// Centro di controllo della Catena di Fiducia del Responsabile
      /// (QR di fiducia + approvazione dispositivi).
      GoRoute(
        path: '/settings/approval-center',
        builder: (context, state) => const ApprovalCenterPage(),
      ),

      /// Schermata per cambiare classe
      GoRoute(
        path: '/settings/class-switcher',
        builder: (context, state) => const ClassSwitcherPage(),
      ),

      /// Schermata per copiare contenuti da un'altra classe
      GoRoute(
        path: '/settings/class-copy',
        builder: (context, state) => const ClassCopyPage(),
      ),

      /// Procedura guidata per associare un nuovo dispositivo.
      GoRoute(
        path: '/settings/associate-device',
        builder: (context, state) => const AssociateDeviceScreen(),
      ),

      /// Log di sincronizzazione Nearby.
      GoRoute(
        path: '/settings/sync-log',
        builder: (context, state) => const SyncLogPage(),
      ),

      /// Risoluzione conflitti di sincronizzazione.
      GoRoute(
        path: '/settings/sync-conflicts',
        builder: (context, state) => const ConflictResolutionPage(),
      ),

      // ═══════════════════════════════════════════════════════════════════
      // SUPPLENZE TEMPORANEE - Delega sicura del registro
      // ═══════════════════════════════════════════════════════════════════

      /// Hub del modulo: deleghe create (Titolare) e ricevute (Supplente).
      GoRoute(
        path: '/substitutes',
        builder: (context, state) => const SubstituteCenterPage(),
      ),

      /// Creazione di una nuova delega (Titolare): scelta Supplente + durata
      /// → QR Code di delega temporanea.
      GoRoute(
        path: '/substitutes/create',
        builder: (context, state) => const CreateSubstituteDelegationPage(),
      ),

      /// Scansione del QR di delega (Supplente) e di consegna/revoca.
      GoRoute(
        path: '/substitutes/scan',
        builder: (context, state) => const ScanSubstituteDelegationPage(),
      ),

      /// Registro supplenza: presenze + note di lezione, consegna dati.
      GoRoute(
        path: '/substitutes/register',
        builder: (context, state) {
          final extra = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : const <String, dynamic>{};
          return SubstituteRegisterPage(
            delegationId: extra['delegationId'] as String?,
          );
        },
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
          final extra = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : const <String, dynamic>{};
          final catechesi = extra['catechesi'] as Catechesi?;
          return CatechesiEditPage(existing: catechesi);
        },
      ),

      /// Dettaglio completo di un contenuto catechetico con foto,
      /// riferimenti biblici e link esterni.
      GoRoute(
        path: '/catechesi/detail',
        builder: (context, state) {
          final extra = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : const <String, dynamic>{};
          final catechesi = extra['catechesi'] as Catechesi?;
          return CatechesiDetailPage(catechesi: catechesi!);
        },
      ),
    ],
  );
});
