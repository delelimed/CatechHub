// ─────────────────────────────────────────────────────────────────────────
// substitute_center_page.dart — hub del modulo "Supplenze Temporanee"
// ─────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_service.dart';
import '../../core/providers/current_class_provider.dart';
import '../../shared/models/substitute_delegation.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../classes/classes_provider.dart';
import 'substitute_actions.dart';
import 'substitute_providers.dart';

class SubstituteCenterPage extends ConsumerWidget {
  const SubstituteCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delegationsAsync = ref.watch(substituteDelegationsProvider);
    final me = AuthService.getCatechistId();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppScaffold(
      title: 'Supplenze',
      child: delegationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
        data: (delegations) {
          final owned = delegations
              .where((d) => d.ownerCatechistId == me)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final received = delegations
              .where((d) => d.substituteCatechistId == me)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _IntroCard(
                isDark: isDark,
                canCreate: _hasOwnClass(ref),
                onNewDelegation: () => context.push('/substitutes/create'),
                onScan: () => context.push('/substitutes/scan'),
              ),
              const SizedBox(height: 24),
              ..._ownerSection(context, ref, owned, isDark),
              ..._substituteSection(context, ref, received, isDark),
              if (owned.isEmpty && received.isEmpty)
                const _EmptyHub()
              else
                const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

/// Verifica che il catechista locale appartenga ad almeno una classe
/// (prerequisito per creare una delega da Titolare).
bool _hasOwnClass(WidgetRef ref) {
  final classesAsync = ref.watch(classesStreamProvider);
  const localId = AuthService.localUserId;
  return classesAsync.maybeWhen(
    data: (classes) => classes.any((c) => c.catechistIds.contains(localId)),
    orElse: () => false,
  );
}

/// Apre la classe delegata: richiede che la delega sia attiva in questo
/// istante e poi imposta la classe corrente.
Future<void> _openClass(
  BuildContext context,
  WidgetRef ref,
  SubstituteDelegation d,
) async {
  if (!d.isActiveAt(DateTime.now().toUtc())) return;
  await ref.read(currentClassProvider.notifier).setClass(d.classId);
  if (context.mounted) context.go('/');
}

// ─────────────────────────────── Sezioni ───────────────────────────────

/// Sezione "deleghe create" (ruolo Titolare): mostra le supplenze che il
/// catechista locale ha concesso ad altri catechisti.
List<Widget> _ownerSection(
  BuildContext context,
  WidgetRef ref,
  List<SubstituteDelegation> items,
  bool isDark,
) {
  if (items.isEmpty) return const [];
  return [
    _sectionHeader(isDark, 'Deleghe create (Titolare)'),
    ...items.map(
      (d) => SubstituteDelegationCard(
        delegation: d,
        isOwner: true,
        onQr: () => showDelegationQr(context, d),
        onAcquire: () => acquireHandover(context, ref, d),
        onTerminate: () => terminateDelegation(context, ref, d),
        onOpenClass: () => _openClass(context, ref, d),
      ),
    ),
    const SizedBox(height: 24),
  ];
}

/// Sezione "supplenze ricevute" (ruolo Supplente): mostra le classi in cui
/// il catechista locale è stato delegato dal Titolare.
List<Widget> _substituteSection(
  BuildContext context,
  WidgetRef ref,
  List<SubstituteDelegation> items,
  bool isDark,
) {
  if (items.isEmpty) return const [];
  return [
    _sectionHeader(isDark, 'Supplenze ricevute (Supplente)'),
    ...items.map(
      (d) => SubstituteDelegationCard(
        delegation: d,
        isOwner: false,
        onQr: null,
        onAcquire: null,
        onTerminate: null,
        onOpenClass: () => _openClass(context, ref, d),
      ),
    ),
    const SizedBox(height: 24),
  ];
}

Widget _sectionHeader(bool isDark, String title) {
  return Text(
    title,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.bold,
      letterSpacing: 1,
      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
    ),
  );
}

// ─────────────────────────────── Widgets ───────────────────────────────

/// Card riepilogo di una singola supplenza (Titolare o Supplente).
class SubstituteDelegationCard extends StatelessWidget {
  final SubstituteDelegation delegation;
  final bool isOwner;
  final VoidCallback? onQr;
  final VoidCallback? onAcquire;
  final VoidCallback? onTerminate;
  final VoidCallback? onOpenClass;

  const SubstituteDelegationCard({
    super.key,
    required this.delegation,
    required this.isOwner,
    this.onQr,
    this.onAcquire,
    this.onTerminate,
    this.onOpenClass,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final status = _statusOf(delegation);
    final active = delegation.status == SubstituteDelegationStatus.active;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainer : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: status.color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  delegation.className,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _StatusChip(label: status.label, color: status.color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isOwner
                ? 'Supplente: ${delegation.substituteName}'
                : 'Titolare: ${delegation.ownerName}',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isOwner && onQr != null)
                _actionButton(
                  label: 'QR delega',
                  icon: Icons.qr_code_2_rounded,
                  onPressed: onQr,
                ),
              if (isOwner && onAcquire != null && !delegation.dataCollected)
                _actionButton(
                  label: 'Acquisisci dati',
                  icon: Icons.download_rounded,
                  onPressed: onAcquire,
                ),
              if (isOwner && onTerminate != null)
                _actionButton(
                  label: 'Termina',
                  icon: Icons.block_rounded,
                  destructive: true,
                  onPressed: onTerminate,
                ),
              if (!isOwner && onOpenClass != null && active)
                _actionButton(
                  label: 'Apri registro',
                  icon: Icons.menu_book_rounded,
                  onPressed: onOpenClass,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool destructive = false,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: destructive
          ? OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade200),
            )
          : null,
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }

  static _StatusInfo _statusOf(SubstituteDelegation d) {
    switch (d.status) {
      case SubstituteDelegationStatus.completed:
        return _StatusInfo(label: 'Completata', color: Colors.green);
      case SubstituteDelegationStatus.revoked:
        return _StatusInfo(label: 'Revocata', color: Colors.red);
      case SubstituteDelegationStatus.expired:
        return _StatusInfo(label: 'Scaduta', color: Colors.orange);
      default:
        return _StatusInfo(label: 'Attiva', color: Colors.blue);
    }
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _StatusInfo {
  final String label;
  final Color color;
  const _StatusInfo({required this.label, required this.color});
}

/// Card introduttiva con le azioni principali del modulo.
class _IntroCard extends StatelessWidget {
  final bool isDark;
  final bool canCreate;
  final VoidCallback onNewDelegation;
  final VoidCallback onScan;

  const _IntroCard({
    required this.isDark,
    required this.canCreate,
    required this.onNewDelegation,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainer : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? colorScheme.outline.withValues(alpha: 0.2)
              : Colors.blue.shade100,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Delega temporanea del registro',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Il Titolare delega un altro catechista a prendere le presenze e '
            'le note di lezione per un periodo definito. La supplenza è '
            'revocabile in qualsiasi momento.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: canCreate ? onNewDelegation : () => _noOwnClass(context),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: const Text('Nuova supplenza'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onScan,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Scansiona QR'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _noOwnClass(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Seleziona prima una classe di tua appartenenza dalla schermata '
          'principale.',
        ),
      ),
    );
  }
}

/// Stato vuoto: nessuna supplenza creata né ricevuta.
class _EmptyHub extends StatelessWidget {
  const _EmptyHub();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(28),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.swap_horiz_rounded,
            size: 48,
            color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            'Nessuna supplenza',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Le deleghe create o ricevute compariranno qui.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}