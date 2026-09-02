// ══════════════════════════════════════════════════════════════════════════════
// onboarding_page.dart — CatechHub (flusso di primo avvio)
//
// Struttura a 4 schermate:
//   STEP 0 — Informativa e richiesta permessi CONTESTUALI:
//     illustra i permessi necessari (Notifiche, P2P/Bluetooth, Fotocamera,
//     Foto/media) SENZA attivarli in blocco: la richiesta nativa del sistema
//     operativo parte esclusivamente al click dell'utente sul relativo pulsante.
//   STEP 1 — Creazione del profilo (TUTTI i dispositivi):
//     nome, cognome e telefono; genera l'id univoco del catechista
//     (deterministico da nome e cognome, condiviso su tutti i dispositivi).
//   STEP 2 — Selezione della modalità operativa (3 pulsanti):
//     [Modalità Responsabile Catechistico]
//     [Modalità Autonoma]
//     [Modalità Associato]
//   STEP 3 — Dati della parrocchia (solo Modalità Responsabile).
//
// A seconda della modalità scelta vengono salvati ruolo, modalità operativa
// (app_mode) e configurazione parrocchiale, poi l'utente viene reindirizzato
// al flusso successivo (login/profilo oppure associazione P2P).
//
// MODALITÀ RESPONSABILE:
//   Prima di procedere al login viene chiesto subito il NOME della parrocchia,
//   la DIOCESI e l'ANNO CATECHISTICO corrente (passo "Dati della parrocchia").
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/services/bluetooth_permission_service.dart';
import '../../../../core/auth/auth_service.dart';
import '../../../../core/storage/local_database.dart';
import '../../../../features/responsabile/parish_config_repository.dart';
import '../../../../shared/models/user_role.dart';
import '../../../../shared/utils/anno_catechistico.dart';

/// Modalità operativa scelta durante l'onboarding (spec: app_mode).
enum _OnboardingMode {
  /// Gestione centralizzata della parrocchia (ruolo Responsabile).
  responsabile,

  /// Uso autonomo del singolo catechista (creazione classe).
  normal,

  /// Il dispositivo riceve account e classe da un altro dispositivo via P2P.
  join,
}

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  @override
  void initState() {
    super.initState();
    // Precompila l'anno catechistico corrente (es. "2026-2027").
    _annoCatechisticoCtrl.text = currentCatechisticYear();
  }

  bool _notificationGranted = false;
  bool _cameraGranted = false;
  bool _locationGranted = false;
  bool _bluetoothGranted = false;
  bool _photosGranted = false;

  bool _notificationRequested = false;
  bool _cameraRequested = false;
  bool _locationRequested = false;
  bool _bluetoothRequested = false;
  bool _photosRequested = false;

  /// 0 = permessi contestuali, 1 = creazione profilo (tutti i dispositivi),
  /// 2 = selezione modalità, 3 = dati della parrocchia (solo Responsabile).
  int _step = 0;

  String? _errorMessage;

  _OnboardingMode? _selectedMode;

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _classNameCtrl = TextEditingController();
  final _nomeParrocchiaCtrl = TextEditingController();
  final _diocesiCtrl = TextEditingController();
  final _annoCatechisticoCtrl = TextEditingController();

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _classNameCtrl.dispose();
    _nomeParrocchiaCtrl.dispose();
    _diocesiCtrl.dispose();
    _annoCatechisticoCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // RICHIESTA PERMESSI (OS prompt SOLO su interazione utente)
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _requestNotificationPermission() async {
    HapticFeedback.lightImpact();
    setState(() {
      _notificationRequested = true;
      _errorMessage = null;
    });

    final status = await Permission.notification.request();
    if (mounted && (status.isGranted || status.isLimited)) {
      setState(() => _notificationGranted = true);
    } else if (mounted && (status.isPermanentlyDenied || status.isRestricted)) {
      await _showSettingsDialog(
        'Notifiche disattivate',
        'Per ricevere avvisi di aggiornamento, attiva le notifiche dalle impostazioni del dispositivo.',
      );
    }
  }

  Future<void> _requestCameraPermission() async {
    HapticFeedback.lightImpact();
    setState(() {
      _cameraRequested = true;
      _errorMessage = null;
    });

    final status = await Permission.camera.request();
    if (mounted && (status.isGranted || status.isLimited)) {
      setState(() => _cameraGranted = true);
    } else if (mounted && (status.isPermanentlyDenied || status.isRestricted)) {
      await _showSettingsDialog(
        'Fotocamera non autorizzata',
        'Per scansionare i codici QR di associazione o condivisione offline, attiva la fotocamera dalle impostazioni del dispositivo.',
      );
    }
  }

  Future<void> _requestLocationPermission() async {
    HapticFeedback.lightImpact();
    setState(() {
      _locationRequested = true;
      _errorMessage = null;
    });

    final status = await Permission.locationWhenInUse.request();
    if (mounted && (status.isGranted || status.isLimited)) {
      setState(() => _locationGranted = true);
    } else if (mounted && (status.isPermanentlyDenied || status.isRestricted)) {
      await _showSettingsDialog(
        'Posizione non autorizzata',
        'Per la sincronizzazione Bluetooth tra catechisti, autorizza la posizione dalle impostazioni del dispositivo. '
            'CatechHub non usa la tua posizione per geolocalizzazione.',
      );
    }
  }

  Future<void> _requestBluetoothPermission() async {
    HapticFeedback.lightImpact();
    setState(() {
      _bluetoothRequested = true;
      _errorMessage = null;
    });

    final result = await BluetoothPermissionService.checkAndRequestPermissions(
      context: context,
    );

    if (!mounted) return;
    if (result.allGranted) {
      setState(() => _bluetoothGranted = true);
    } else if (result.hasPermanentlyDenied) {
      await _showSettingsDialog(
        'Permessi non autorizzati',
        result.errorMessage ??
            'Per sincronizzare i dati con altri catechisti, attiva i permessi nelle impostazioni del dispositivo.',
      );
    }
  }

  Future<void> _requestPhotosPermission() async {
    HapticFeedback.lightImpact();
    setState(() {
      _photosRequested = true;
      _errorMessage = null;
    });

    final status = await Permission.photos.request();
    if (mounted && (status.isGranted || status.isLimited)) {
      setState(() => _photosGranted = true);
    } else if (mounted && (status.isPermanentlyDenied || status.isRestricted)) {
      await _showSettingsDialog(
        'Galleria non autorizzata',
        'Per allegare foto di ragazzi, documenti e verbali dagli allegati, '
            'autorizza l\'accesso alla galleria dalle impostazioni del dispositivo.',
      );
    }
  }

  Future<void> _showSettingsDialog(String title, String content) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Più tardi'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Apri impostazioni'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // SELEZIONE MODALITÀ OPERATIVA
  // ─────────────────────────────────────────────────────────────────────────────

  void _selectMode(_OnboardingMode mode) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedMode = mode;
      _errorMessage = null;
    });
    if (mode == _OnboardingMode.responsabile) {
      // Mostra subito l'informativa beta non appena l'utente seleziona
      // la modalità Responsabile.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Evita dialog multipli se già aperto rapidamente
        if (_selectedMode != _OnboardingMode.responsabile) return;
        _showResponsabileBetaDialog();
      });
    }
  }

  Future<void> _showResponsabileBetaDialog() async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.construction_rounded,
                  color: Colors.amber.shade800, size: 20),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Modalità Responsabile\n— versione beta',
                style: TextStyle(fontSize: 16, height: 1.2),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 14, color: Colors.orange.shade800),
                    const SizedBox(width: 6),
                    Text(
                      'BETA — non completa',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'La Modalità Responsabile è attualmente in versione beta e non è ancora completa. '
                'La sincronizzazione tra dispositivi in questa modalità non è ancora funzionante.',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade800, height: 1.45),
              ),
              const SizedBox(height: 10),
              Text(
                'Ti invitiamo ad attendere la versione 2.0 per l\'uso reale e ad utilizzare nel frattempo la Modalità Normale, stabile e pienamente funzionante.',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade800, height: 1.45),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF174A7E).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: const Color(0xFF174A7E).withValues(alpha: 0.15)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.visibility_rounded,
                        size: 16, color: Color(0xFF174A7E)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'La modalità Responsabile configurabile ora serve solo come anteprima per mostrare come sarà in futuro e per raccogliere consigli sulle funzionalità da integrare.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            height: 1.4,
                            fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('normale'),
            child: const Text('Usa modalità normale'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF174A7E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(ctx).pop('beta'),
            child: const Text('Continua in anteprima'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (result == 'normale') {
      setState(() => _selectedMode = _OnboardingMode.normal);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Modalità Normale selezionata — stabile e con sincronizzazione funzionante.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else if (result == 'beta') {
      // Resta su Responsabile, ma informa con feedback leggero
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Modalità Responsabile (beta) — sincronizzazione non disponibile fino alla v2.0.'),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Salva il profilo anagrafico (nome, cognome, telefono) e genera
  /// l'id univoco del catechista (deterministico da nome e cognome) che
  /// identifica la persona su tutti i suoi dispositivi. Poi passa alla
  /// scelta della modalità operativa.
  Future<void> _confirmProfile() async {
    final first = _firstNameCtrl.text.trim();
    final last = _lastNameCtrl.text.trim();
    if (first.isEmpty || last.isEmpty) {
      setState(() => _errorMessage = 'Nome e cognome sono obbligatori.');
      return;
    }

    final id = AuthService.generateCatechistId(
      first,
      last,
      _phoneCtrl.text.trim(),
    );
    final box = LocalDatabase.auth();
    await box.put('first_name', first);
    await box.put('last_name', last);
    await box.put(
      'phone_number',
      _phoneCtrl.text.trim().replaceAll(RegExp(r'\s+'), ' '),
    );
    AuthService.storeCatechistId(id);

    setState(() {
      _step = 2;
      _errorMessage = null;
    });
  }

  /// Applica ruolo, app_mode e configurazione parrocchiale in base alla
  /// modalità scelta, poi reindirizza al flusso successivo.
  Future<void> _confirmMode() async {
    final mode = _selectedMode;
    if (mode == null) {
      setState(() => _errorMessage = 'Seleziona una modalità per continuare.');
      return;
    }

    // In Modalità Responsabile si chiede il nome della parrocchia (STEP 3);
    // in Modalità Autonoma si chiede il nome della classe da creare (STEP 4).
    if (mode == _OnboardingMode.responsabile) {
      setState(() {
        _step = 3;
        _errorMessage = null;
      });
    } else if (mode == _OnboardingMode.normal) {
      setState(() {
        _step = 4;
        _errorMessage = null;
      });
    } else {
      // Modalità Associato: nessun dato aggiuntivo, si passa all'associazione.
      await _finalizeProfile(createClass: false, role: UserRole.catechista);
    }
  }

  /// Finalizza il profilo (nome/cognome/telefono + ruolo + modalità) e crea
  /// eventualmente la classe iniziale, poi rimanda al login. Il login mostrerà
  /// così SOLO il pulsante di sblocco con le credenziali Android (nessuna
  /// richiesta di nome/cognome, già raccolti in onboarding).
  Future<void> _finalizeProfile({
    required bool createClass,
    String? groupName,
    required UserRole role,
  }) async {
    final auth = AuthService();
    await auth.setupInitialProfile(
      firstName: _firstNameCtrl.text.trim(),
      lastName: _lastNameCtrl.text.trim(),
      phoneNumber: _phoneCtrl.text.trim(),
      createClass: createClass,
      groupName: groupName,
      role: role,
    );

    final box = LocalDatabase.auth();
    await box.put('onboarding_completed', true);

    if (!mounted) return;
    // La Modalità Associato apre direttamente l'associazione P2P.
    if (role == UserRole.catechista && !createClass) {
      context.go('/onboarding-sync');
    } else {
      context.go('/login');
    }
  }

  /// Conferma i dati della parrocchia (Modalità Responsabile) e procede
  /// con il salvataggio del profilo.
  Future<void> _confirmParishData() async {
    final nome = _nomeParrocchiaCtrl.text.trim();
    if (nome.isEmpty) {
      setState(() => _errorMessage = 'Inserisci il nome della parrocchia.');
      return;
    }

    // Salva i dati della parrocchia PRIMA di lasciare l'onboarding: la
    // modalità Responsabile viene forzata così da superare il controllo
    // di scrittura del repository (l'utente non è ancora autenticato).
    await UserRole.setCurrent(UserRole.responsabile);
    final configRepo = ParishConfigRepository();
    await configRepo.forceResponsabileMode(true);
    await configRepo.save(
      configRepo.getConfig().copyWith(
        nomeParrocchia: nome,
        diocesi: _diocesiCtrl.text.trim(),
        annoCatechisticoCorrente: _annoCatechisticoCtrl.text.trim(),
      ),
    );

    // Il profilo viene finalizzato qui: il login mostrerà solo lo sblocco.
    await _finalizeProfile(createClass: false, role: UserRole.responsabile);
  }

  /// Conferma il nome della classe (Modalità Autonoma) e crea la classe
  /// iniziale, poi rimanda al login (che mostrerà solo lo sblocco).
  Future<void> _confirmClassName() async {
    final name = _classNameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Inserisci il nome della classe.');
      return;
    }
    await _finalizeProfile(
      createClass: true,
      groupName: name,
      role: UserRole.catechista,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
      child: _step == 0
          ? _buildPermissionsStep()
          : _step == 1
          ? _buildProfileStep()
          : _step == 2
          ? _buildModeStep()
          : _step == 3
          ? _buildParishStep()
          : _buildClassNameStep(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          if (_step > 0)
            IconButton(
              onPressed: () => setState(() => _step = _step - 1),
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Indietro',
            )
          else
            const SizedBox(width: 48),
            Expanded(
              child: Center(
                child: Text(
                  switch (_step) {
                    0 => 'Benvenuto in CatechHub',
                    1 => 'Crea il tuo profilo',
                    2 => 'Scegli la modalità',
                    3 => 'Dati della parrocchia',
                    _ => 'Nome della classe',
                  },
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF174A7E),
                ),
              ),
            ),
          ),
          if (_step == 0)
            TextButton(
              onPressed: () => setState(() => _step = 1),
              child: const Text('Salta'),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ─── STEP 0: PERMESSI CONTESTUALI ──────────────────────────────────────────

  Widget _buildPermissionsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF174A7E).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                size: 40,
                color: Color(0xFF174A7E),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Prima di iniziare',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Color(0xFF174A7E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Per il corretto funzionamento CatechHub usa alcuni permessi '
              'del dispositivo. Puoi attivarli ora oppure quando ti verranno '
              'richiesti durante l\'uso.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            _buildPermissionCard(
              icon: Icons.notifications_rounded,
              title: 'Notifiche',
              description:
                  'Avvisi di aggiornamento e promemoria degli incontri.',
              granted: _notificationGranted,
              requested: _notificationRequested,
              buttonLabel: 'Attiva le notifiche',
              onRequest: _requestNotificationPermission,
            ),
            _buildPermissionCard(
              icon: Icons.bluetooth_rounded,
              title: 'Connessione locale (P2P)',
              description:
                  'Sincronizzazione diretta tra catechisti via Bluetooth '
                  'e Nearby. Su Android richiede anche il permesso di posizione.',
              granted: _locationGranted && _bluetoothGranted,
              requested: _locationRequested && _bluetoothRequested,
              buttonLabel: 'Attiva la connessione P2P',
              onRequest: () async {
                await _requestBluetoothPermission();
                if (!_locationGranted && !_locationRequested) {
                  await _requestLocationPermission();
                }
              },
            ),
            _buildPermissionCard(
              icon: Icons.qr_code_scanner_rounded,
              title: 'Fotocamera',
              description:
                  'Per scansionare i codici QR di associazione o '
                  'condivisione dei dati tra catechisti.',
              granted: _cameraGranted,
              requested: _cameraRequested,
              buttonLabel: 'Attiva la fotocamera',
              onRequest: _requestCameraPermission,
            ),
            _buildPermissionCard(
              icon: Icons.photo_library_rounded,
              title: 'Foto e media',
              description:
                  'Per allegare foto di ragazzi, documenti e verbali '
                  'dalla galleria del dispositivo.',
              granted: _photosGranted,
              requested: _photosRequested,
              buttonLabel: 'Attiva l\'accesso alla galleria',
              onRequest: _requestPhotosPermission,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => setState(() => _step = 1),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF174A7E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                ),
                child: const Text(
                  'Continua',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionCard({
    required IconData icon,
    required String title,
    required String description,
    required bool granted,
    required bool requested,
    required String buttonLabel,
    required Future<void> Function() onRequest,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: granted
                      ? Colors.green.shade50
                      : const Color(0xFF174A7E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: granted
                      ? Colors.green.shade700
                      : const Color(0xFF174A7E),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF174A7E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade700,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (granted)
            _buildGrantedBadge()
          else if (requested)
            _buildSettingsButton()
          else
            _buildPermissionButton(buttonLabel, () => onRequest()),
        ],
      ),
    );
  }

  Widget _buildPermissionButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF174A7E),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        icon: const Icon(Icons.toggle_on_rounded, size: 24),
        label: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildSettingsButton() {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: openAppSettings,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF174A7E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: const Icon(Icons.settings_rounded, size: 20),
        label: const Text(
          'Attiva dalle impostazioni',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildGrantedBadge() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle_rounded,
          color: Colors.green.shade700,
          size: 20,
        ),
        const SizedBox(width: 6),
        Text(
          'Permesso concesso',
          style: TextStyle(
            color: Colors.green.shade700,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  // ─── STEP 1: CREAZIONE PROFILO (TUTTI I DISPOSITIVI) ──────────────────────

  Widget _buildProfileStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF174A7E).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.person_rounded,
                size: 40,
                color: Color(0xFF174A7E),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Creа il tuo profilo',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF174A7E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Inserisci i tuoi dati: verranno usati per generare un id '
              'univoco del catechista (basato su nome e cognome) condiviso '
              'su tutti i tuoi dispositivi.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _firstNameCtrl,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Nome *',
                hintText: 'Es. Mario',
                prefixIcon: const Icon(Icons.person_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _lastNameCtrl,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Cognome *',
                hintText: 'Es. Rossi',
                prefixIcon: const Icon(Icons.person_outline_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Numero di telefono (facoltativo)',
                hintText: 'Es. 333 1234567',
                prefixIcon: const Icon(Icons.phone_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                isDense: true,
              ),
              onSubmitted: (_) => _confirmProfile(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _confirmProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF174A7E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                label: const Text(
                  'Continua',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ─── STEP 2: SELEZIONE MODALITÀ OPERATIVA ──────────────────────────────────

  Widget _buildModeStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              'Come vuoi usare CatechHub?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF174A7E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Puoi cambiare modalità in qualsiasi momento dalle impostazioni.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            _buildModeCard(
              mode: _OnboardingMode.responsabile,
              icon: Icons.account_balance_rounded,
              title: 'Modalità Responsabile Catechistico',
              description:
                  'Per chi gestisce la programmazione e la struttura '
                  'dell\'intera parrocchia: classi, catechisti, luoghi, presenze '
                  'aggregate e registro GDPR.',
            ),
            _buildModeCard(
              mode: _OnboardingMode.normal,
              icon: Icons.menu_book_rounded,
              title: 'Modalità Autonoma',
              description:
                  'Uso autonomo del singolo catechista: crea la tua '
                  'classe e gestisci il registro in modo indipendente.',
            ),
            _buildModeCard(
              mode: _OnboardingMode.join,
              icon: Icons.group_add_rounded,
              title: 'Modalità Associato',
              description:
                  'Configura rapidamente un nuovo dispositivo ricevendo '
                  'account e classe direttamente da un altro catechista o dal '
                  'Responsabile via P2P (Nearby Share).',
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _confirmMode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF174A7E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                label: Text(
                  _selectedMode == null ? 'Continua' : 'Conferma modalità',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required _OnboardingMode mode,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final isSelected = _selectedMode == mode;
    final isResponsabileBeta = mode == _OnboardingMode.responsabile;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _selectMode(mode),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF174A7E).withValues(alpha: 0.06)
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF174A7E)
                  : Colors.grey.shade200,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF174A7E)
                      : const Color(0xFF174A7E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? Colors.white : const Color(0xFF174A7E),
                  size: 27,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xFF174A7E),
                            ),
                          ),
                        ),
                        if (isResponsabileBeta) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: Colors.orange.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.science_rounded,
                                    size: 12, color: Colors.orange.shade800),
                                const SizedBox(width: 4),
                                Text(
                                  'BETA',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade800,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade700,
                        height: 1.45,
                      ),
                    ),
                    if (isResponsabileBeta) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Versione beta non completa — sincronizzazione non funzionante fino alla v2.0. Solo anteprima per raccogliere feedback.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade800,
                          height: 1.35,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isSelected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: isSelected
                    ? const Color(0xFF174A7E)
                    : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── STEP 2: DATI DELLA PARROCCHIA (SOLO MODALITÀ RESPONSABILE) ──────────

  Widget _buildParishStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF174A7E).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.account_balance_rounded,
                size: 40,
                color: Color(0xFF174A7E),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'La tua parrocchia',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF174A7E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Per completare la configurazione da Responsabile Catechistico '
              'inserisci le informazioni principali della parrocchia. Potrai '
              'modificarle in qualsiasi momento dalle impostazioni.',
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 20, color: Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Anteprima beta — sincronizzazione non disponibile',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Questa modalità è una beta non completa. La sincronizzazione non funziona: attendi la versione 2.0 e usa nel frattempo la Modalità Normale. Questa configurazione serve solo come anteprima per raccogliere consigli su future funzionalità.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.orange.shade900,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nomeParrocchiaCtrl,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Nome della parrocchia *',
                hintText: 'Es. Parrocchia San Francesco',
                prefixIcon: const Icon(Icons.church_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _diocesiCtrl,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Diocesi',
                hintText: 'Es. Diocesi di Roma',
                prefixIcon: const Icon(Icons.account_balance_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _annoCatechisticoCtrl,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Anno catechistico corrente',
                hintText: 'Es. 2026-2027',
                prefixIcon: const Icon(Icons.calendar_month_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                isDense: true,
              ),
              onSubmitted: (_) => _confirmParishData(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _confirmParishData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF174A7E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                label: const Text(
                  'Continua',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ─── STEP 4: NOME DELLA CLASSE (SOLO MODALITÀ AUTONOMA) ──────────────────

  Widget _buildClassNameStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF174A7E).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.groups_rounded,
                size: 40,
                color: Color(0xFF174A7E),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Crea la tua classe',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF174A7E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'In Modalità Autonoma crei subito la tua classe di catechismo. '
              'Potrai aggiungerne altre e gestire i catechisti in seguito.',
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _classNameCtrl,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Nome della classe *',
                hintText: 'Es. Prima elementare, Cresima 2026',
                prefixIcon: const Icon(Icons.groups_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                isDense: true,
              ),
              onSubmitted: (_) => _confirmClassName(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _confirmClassName,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF174A7E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                label: const Text(
                  'Crea classe e accedi',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
