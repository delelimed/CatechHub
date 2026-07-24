import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/services/bluetooth_permission_service.dart';
import '../../../../core/storage/local_database.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _pageController = PageController();
  int _currentPage = 0;

  bool _notificationGranted = false;
  bool _cameraGranted = false;
  bool _bluetoothGranted = false;

  bool _notificationRequested = false;
  bool _cameraRequested = false;
  bool _bluetoothRequested = false;

  String? _errorMessage;

  static const _totalPages = 8;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToNextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _requestNotificationPermission() async {
    HapticFeedback.lightImpact();
    setState(() {
      _notificationRequested = true;
      _errorMessage = null;
    });

    final status = await Permission.notification.request();
    if (status.isGranted || status.isLimited) {
      setState(() => _notificationGranted = true);
    } else if (status.isPermanentlyDenied || status.isRestricted) {
      if (mounted) await _showSettingsDialog(
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
    if (status.isGranted || status.isLimited) {
      setState(() => _cameraGranted = true);
    } else if (status.isPermanentlyDenied || status.isRestricted) {
      if (mounted) await _showSettingsDialog(
        'Fotocamera non autorizzata',
        'Per scansionare i codici QR di associazione o condivisione offline, attiva la fotocamera dalle impostazioni del dispositivo.',
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

    if (result.allGranted) {
      setState(() => _bluetoothGranted = true);
    } else if (result.hasPermanentlyDenied) {
      if (mounted) {
        await _showSettingsDialog(
          'Permessi non autorizzati',
          result.errorMessage ??
              'Per sincronizzare i dati con altri catechisti, attiva i permessi nelle impostazioni del dispositivo.',
        );
      }
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

  Future<void> _completeOnboarding() async {
    final box = LocalDatabase.auth();
    await box.put('onboarding_completed', true);
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with skip button and dots
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentPage < _totalPages - 1)
                    TextButton(
                      onPressed: _completeOnboarding,
                      child: const Text('Salta'),
                    )
                  else
                    const SizedBox(width: 72),
                  _buildPageDots(),
                  const SizedBox(width: 72),
                ],
              ),
            ),
            // Page content
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildWelcomePage(),
                  _buildHowItWorksPage(),
                  _buildDataSensitivityPage(),
                  _buildNotificationPermissionPage(),
                  _buildCameraPermissionPage(),
                  _buildBluetoothPermissionPage(),
                  _buildReadyPage(),
                  _buildLegalDisclaimerPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_totalPages, (i) {
        final isActive = i == _currentPage;
        final status = _pageStatus(i);
        final dotColor = status == 1
            ? Colors.green
            : isActive
                ? const Color(0xFF174A7E)
                : Colors.grey.shade300;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: dotColor,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  int _pageStatus(int index) {
    if (index == 0 || index == 1 || index == 2 || index == _totalPages - 1) return 0;
    if (index == 3 && _notificationGranted) return 1;
    if (index == 4 && _cameraGranted) return 1;
    if (index == 5 && _bluetoothGranted) return 1;
    return index < _currentPage ? -1 : 0;
  }

  Widget _buildPageContainer(Widget child) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: child,
      ),
    );
  }

  // ─── PAGE 1: WELCOME ───────────────────────────────────────────────

  Widget _buildWelcomePage() {
    return _buildPageContainer(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF174A7E).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Icon(Icons.menu_book_rounded, size: 72, color: Color(0xFF174A7E)),
          ),
          const SizedBox(height: 32),
          const Text(
            'CatechHub',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF174A7E)),
          ),
          const SizedBox(height: 12),
          Text(
            'Il tuo registro elettronico di catechismo\nprivacy-first, offline e sicuro',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade700, height: 1.5),
          ),
          const SizedBox(height: 40),
          _buildInfoCard(
            Icons.lock_rounded,
            'Privacy al primo posto',
            'Tutti i dati restano sul tuo dispositivo, cifrati con AES-256-GCM. Nessun cloud, nessun server remoto.',
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            Icons.wifi_off_rounded,
            '100% offline',
            'Nessuna connessione internet necessaria. L\'app funziona sempre, anche in cantina o in montagna.',
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            Icons.bluetooth_rounded,
            'Sincronizzazione P2P',
            'Condividi i dati con altri catechisti direttamente via Bluetooth o con QR, senza passare da server esterni.',
          ),
          const SizedBox(height: 40),
          _buildNextButton('Continua'),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ─── PAGE 2: HOW IT WORKS ──────────────────────────────────────────

  Widget _buildHowItWorksPage() {
    return _buildPageContainer(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.touch_app_rounded, size: 64, color: Color(0xFF174A7E)),
          const SizedBox(height: 24),
          const Text(
            'Come funziona',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF174A7E)),
          ),
          const SizedBox(height: 28),
          _buildStepCard(
            '1',
            'Autenticazione',
            'Sblocchi l\'app con impronta, volto o PIN del telefono. Niente password da ricordare.',
          ),
          const SizedBox(height: 12),
          _buildStepCard(
            '2',
            'Gestione dati',
            'Inserisci ragazzi, segna presenze, programma incontri e gestisci documenti. Tutto offline.',
          ),
          const SizedBox(height: 12),
          _buildStepCard(
            '3',
            'Condivisione sicura',
            'Scambia dati con altri catechisti via QR code o Bluetooth. I dati viaggiano cifrati.',
          ),
          const SizedBox(height: 12),
          _buildStepCard(
            '4',
            'Backup cifrato',
            'Esporta un backup con password dedicata. Solo tu puoi ripristinarlo.',
          ),
          const SizedBox(height: 32),
          _buildNextButton('Continua'),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ─── PAGE 3: DATA SENSITIVITY AWARENESS ───────────────────────────

  Widget _buildDataSensitivityPage() {
    return _buildPageContainer(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.shield_rounded, size: 64, color: Color(0xFF174A7E)),
          const SizedBox(height: 24),
          const Text(
            'Gestione dati sensibili',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF174A7E)),
          ),
          const SizedBox(height: 12),
          const Text(
            'Con CatechHub gestisci dati di minori: dati sensibili che richiedono particolare attenzione.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Cosa puoi fare per proteggere i dati:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF174A7E)),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                _SensitivityTip(
                  icon: Icons.lock_outline_rounded,
                  text: 'Tieni il telefono sempre bloccato con PIN, impronta o riconoscimento facciale',
                ),
                SizedBox(height: 10),
                _SensitivityTip(
                  icon: Icons.remove_red_eye_outlined,
                  text: 'Non lasciare il dispositivo incustodito con l\'app aperta',
                ),
                SizedBox(height: 10),
                _SensitivityTip(
                  icon: Icons.share_outlined,
                  text: 'Condividi dati solo con catechisti di cui ti fidi e che hanno diritto a trattare i dati a pari tuo, sempre tramite Bluetooth o QR code',
                ),
                SizedBox(height: 10),
                _SensitivityTip(
                  icon: Icons.backup_outlined,
                  text: 'Fai backup periodici con password dedicata e conservali in un luogo sicuro',
                ),
                SizedBox(height: 10),
                _SensitivityTip(
                  icon: Icons.phone_iphone_rounded,
                  text: 'Se cambi dispositivo, trasferisci i dati in modo sicuro e cancella quelli dal vecchio telefono',
                ),
                SizedBox(height: 10),
                _SensitivityTip(
                  icon: Icons.update_rounded,
                  text: 'Mantieni l\'app aggiornata per avere sempre le ultime protezioni di sicurezza',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF174A7E).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, color: Color(0xFF174A7E), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'I tuoi dati non escono mai dal dispositivo se non durante sincronizzazioni volontarie e cifrate.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF174A7E), height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _buildNextButton('Continua'),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ─── PAGE 4: NOTIFICATION PERMISSION ───────────────────────────────

  Widget _buildNotificationPermissionPage() {
    return _buildPageContainer(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Icon(
            _notificationGranted ? Icons.check_circle_rounded : Icons.notifications_rounded,
            size: 80,
            color: _notificationGranted ? Colors.green : const Color(0xFF174A7E),
          ),
          const SizedBox(height: 24),
          const Text(
            'Permesso: Notifiche',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF174A7E)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 6))],
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A cosa serve:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF174A7E)),
                ),
                SizedBox(height: 8),
                Text(
                  'Le notifiche permettono a CatechHub di avvisarti quando è disponibile un aggiornamento dell\'app.',
                  style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
                ),
                SizedBox(height: 16),
                Text(
                  'Perché ne abbiamo bisogno:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF174A7E)),
                ),
                SizedBox(height: 8),
                Text(
                  'Per garantire la sicurezza dei dati, è importante che tu abbia sempre l\'ultima versione dell\'app. '
                  'Le notifiche ci permettono di informarti tempestivamente.',
                  style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          if (!_notificationGranted)
            _buildPermissionButton(
              'Attiva notifiche',
              _requestNotificationPermission,
              _notificationRequested,
            )
          else
            _buildGrantedBadge(),
          const SizedBox(height: 24),
          if (_notificationGranted || _notificationRequested)
            _buildNextButton('Continua')
          else
            Text(
              'Puoi saltare e attivare le notifiche più tardi dalle Impostazioni.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ─── PAGE 4: CAMERA PERMISSION ─────────────────────────────────────

  Widget _buildCameraPermissionPage() {
    return _buildPageContainer(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Icon(
            _cameraGranted ? Icons.check_circle_rounded : Icons.camera_alt_rounded,
            size: 80,
            color: _cameraGranted ? Colors.green : const Color(0xFF174A7E),
          ),
          const SizedBox(height: 24),
          const Text(
            'Permesso: Fotocamera',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF174A7E)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 6))],
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A cosa serve:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF174A7E)),
                ),
                SizedBox(height: 8),
                Text(
                  'La fotocamera serve per scansionare i codici QR durante la condivisione dei dati '
                  'e il pairing Bluetooth con altri catechisti.',
                  style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
                ),
                SizedBox(height: 16),
                Text(
                  'Perché ne abbiamo bisogno:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF174A7E)),
                ),
                SizedBox(height: 8),
                Text(
                  'I QR code sono il metodo più sicuro per scambiare chiavi crittografiche e dati '
                  'tra dispositivi. La fotocamera è necessaria per leggerli. Nessuna foto o video '
                  'viene mai registrato o inviato a server esterni.',
                  style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          if (!_cameraGranted)
            _buildPermissionButton(
              'Attiva fotocamera',
              _requestCameraPermission,
              _cameraRequested,
            )
          else
            _buildGrantedBadge(),
          const SizedBox(height: 24),
          if (_cameraGranted || _cameraRequested)
            _buildNextButton('Continua')
          else
            Text(
              'Puoi saltare e attivare la fotocamera più tardi dalle Impostazioni.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ─── PAGE 5: CONNESSIONE PERMISSION ────────────────────────────────

  Widget _buildBluetoothPermissionPage() {
    return _buildPageContainer(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Icon(
            _bluetoothGranted ? Icons.check_circle_rounded : Icons.bluetooth_rounded,
            size: 80,
            color: _bluetoothGranted ? Colors.green : const Color(0xFF174A7E),
          ),
          const SizedBox(height: 24),
          const Text(
            'Permessi: Connessione',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF174A7E)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 6))],
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A cosa serve:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF174A7E)),
                ),
                SizedBox(height: 8),
                Text(
                  'Bluetooth e Wi-Fi permettono la sincronizzazione diretta tra dispositivi di catechisti '
                  'vicini, senza bisogno di internet.',
                  style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
                ),
                SizedBox(height: 16),
                Text(
                  'Perché ne abbiamo bisogno:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF174A7E)),
                ),
                SizedBox(height: 8),
                Text(
                  'CatechHub sincronizza i dati tra catechisti in modalità peer-to-peer via Bluetooth e Wi-Fi Direct. '
                  'I dati vengono cifrati end-to-end con chiavi ECDH. Nessun dato transita su internet. '
                  'La connessione è attiva solo durante le sincronizzazioni volontarie.',
                  style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          if (!_bluetoothGranted)
            _buildPermissionButton(
              'Attiva connessioni',
              _requestBluetoothPermission,
              _bluetoothRequested,
            )
          else
            _buildGrantedBadge(),
          const SizedBox(height: 24),
          if (_bluetoothGranted || _bluetoothRequested)
            _buildNextButton('Continua')
          else
            Text(
              'Puoi saltare e attivare le connessioni più tardi dalle Impostazioni.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ─── PAGE 6: READY ─────────────────────────────────────────────────

  Widget _buildReadyPage() {
    final allGranted = _notificationGranted && _cameraGranted && _bluetoothGranted;
    final someSkipped = !_notificationGranted || !_cameraGranted || !_bluetoothGranted;

    return _buildPageContainer(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Icon(
            allGranted ? Icons.celebration_rounded : Icons.rocket_launch_rounded,
            size: 80,
            color: const Color(0xFF174A7E),
          ),
          const SizedBox(height: 24),
          Text(
            allGranted ? 'Tutto pronto!' : 'Pronto per iniziare!',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF174A7E)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 6))],
            ),
            child: Column(
              children: [
                _buildPermissionSummary('Notifiche', _notificationGranted),
                const SizedBox(height: 8),
                _buildPermissionSummary('Fotocamera', _cameraGranted),
                const SizedBox(height: 8),
                _buildPermissionSummary('Connessione', _bluetoothGranted),
              ],
            ),
          ),
          if (someSkipped) ...[
            const SizedBox(height: 16),
            Text(
              'Puoi attivare i permessi mancanti in qualsiasi momento dalle Impostazioni.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 8),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _completeOnboarding,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF174A7E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 2,
              ),
              child: const Text(
                'Inizia ad usare CatechHub',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ─── PAGE 8: LEGAL DISCLAIMER ──────────────────────────────────────────

  Widget _buildLegalDisclaimerPage() {
    return _buildPageContainer(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.gavel_rounded, size: 64, color: Color(0xFF174A7E)),
          const SizedBox(height: 24),
          const Text(
            'Disclaimer legale',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF174A7E)),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Con l\'utilizzo di CatechHub, dichiari e confermi:',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF174A7E)),
                ),
                const SizedBox(height: 16),
                _buildDisclaimerPoint(
                  Icons.shield_rounded,
                  'CatechHub non invia dati personali a server esterni. Tutti i dati rimangono esclusivamente sul tuo dispositivo, cifrati con AES-256-GCM.',
                ),
                const SizedBox(height: 12),
                _buildDisclaimerPoint(
                  Icons.person_outline_rounded,
                  'Il titolare del trattamento dei dati dei minori seguiti sei TU (catechista/parroco). CatechHub è solo lo strumento tecnico che ti mette a disposizione.',
                ),
                const SizedBox(height: 12),
                _buildDisclaimerPoint(
                  Icons.shield_moon_rounded,
                  'Ti assumi la piena responsabilità di proteggere il tuo dispositivo (PIN, impronta, volto, aggiornamenti OS, blocco schermo). La sicurezza dei dati dipende dalla custodia del tuo cellulare.',
                ),
                const SizedBox(height: 12),
                _buildDisclaimerPoint(
                  Icons.backup_rounded,
                  'Sei responsabile di eseguito a effettuare backup cifrati periodici e a custodirne le password in luogo sicuro. La perdita del dispositivo senza backup comporta la perdita irreversibile dei dati.',
                ),
                const SizedBox(height: 12),
                _buildDisclaimerPoint(
                  Icons.gavel_rounded,
                  'L\'uso di CatechHub non solleva da obblighi GDPR, normativa canonica e normative locali sulla tutela dei minori. Sei tenuto a rispettare ogni adempimento di legge.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          _buildNextButton('Accetto e inizio'),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDisclaimerPoint(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: const Color(0xFF174A7E)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.5),
          ),
        ),
      ],
    );
  }

  // ─── HELPERS ────────────────────────────────────────────────────────

  Widget _buildInfoCard(IconData icon, String title, String description) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF174A7E).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF174A7E), size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF174A7E))),
                const SizedBox(height: 4),
                Text(description, style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard(String number, String title, String description) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFF174A7E),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF174A7E))),
                const SizedBox(height: 4),
                Text(description, style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionButton(String label, VoidCallback onPressed, bool requested) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: requested ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF174A7E),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
        ),
        icon: const Icon(Icons.toggle_on_rounded, size: 28),
        label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildGrantedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 22),
          const SizedBox(width: 8),
          Text('Permesso concesso', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildNextButton(String label) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _goToNextPage,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF174A7E),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
        ),
        child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildPermissionSummary(String name, bool granted) {
    return Row(
      children: [
        Icon(
          granted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          color: granted ? Colors.green : Colors.grey.shade400,
          size: 22,
        ),
        const SizedBox(width: 10),
        Text(
          name,
          style: TextStyle(
            fontSize: 15,
            color: granted ? Colors.black87 : Colors.grey.shade500,
          ),
        ),
        const Spacer(),
        Text(
          granted ? 'Concesso' : 'Saltato',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: granted ? Colors.green.shade700 : Colors.grey.shade500,
          ),
        ),
      ],
    );
  }
}

class _SensitivityTip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SensitivityTip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF174A7E)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
          ),
        ),
      ],
    );
  }
}
