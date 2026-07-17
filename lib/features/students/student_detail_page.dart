import 'package:flutter/material.dart';

import '../../shared/widgets/app_scaffold.dart';

/// Pagina di dettaglio legacy / WIP: mostra dati anagrafici fissi (nome
/// fittizio "Mario Rossi"), sezioni genitori e azioni future non ancora
/// implementate (storico appelli, modifica dati, presenze).
/// File ereditato da una versione precedente; attualmente sostituita
/// nella navigazione principale da [StudentQuickViewPage].
/// Si appoggia a [AppScaffold] senza repository sottostante.
class StudentDetailPage extends StatelessWidget {
  const StudentDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    const name = 'Mario Rossi';

    return AppScaffold(
      title: 'Scheda ragazzo',

      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          /// =========================
          /// HEADER PROFILO
          /// =========================
          _ProfileHeader(name: name),

          const SizedBox(height: 16),

          /// =========================
          /// DATI BASE
          /// =========================
          const _Section(
            title: 'Dati ragazzo',
            children: [
              _InfoRow(label: 'Telefono', value: '3331234567'),
              _InfoRow(label: 'Classe', value: '3ª Elementare'),
            ],
          ),

          const SizedBox(height: 16),

          /// =========================
          /// GENITORI
          /// =========================
          const _Section(
            title: 'Genitori',
            children: [
              _InfoRow(label: 'Madre', value: 'Maria Rossi'),
              _InfoRow(label: 'Cellulare madre', value: '333222111'),

              SizedBox(height: 8),

              _InfoRow(label: 'Padre', value: 'Luca Rossi'),
              _InfoRow(label: 'Cellulare padre', value: '333444555'),
            ],
          ),

          const SizedBox(height: 16),

          /// =========================
          /// AZIONI FUTURE (placeholder)
          /// =========================
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Attività',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF174A7E),
                  ),
                ),
                const SizedBox(height: 12),

                _ActionButton(
                  icon: Icons.history,
                  label: 'Storico appelli',
                  onTap: () {},
                ),

                _ActionButton(
                  icon: Icons.edit_note,
                  label: 'Modifica dati',
                  onTap: () {},
                ),

                _ActionButton(
                  icon: Icons.event,
                  label: 'Presenze',
                  onTap: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// =========================
/// HEADER
/// =========================
class _ProfileHeader extends StatelessWidget {
  final String name;

  const _ProfileHeader({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            Colors.blue.shade50.withValues(alpha: 0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: const Color(0xFF174A7E),
            child: Text(
              name.isNotEmpty ? name[0] : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF174A7E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Scheda anagrafica ragazzo',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// =========================
/// SECTION
/// =========================
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF174A7E),
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

/// =========================
/// INFO ROW
/// =========================
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// =========================
/// ACTION BUTTON
/// =========================
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: const Color(0xFF174A7E)),
      title: Text(label),
      trailing: const Icon(
        Icons.arrow_forward_ios,
        size: 14,
        color: Colors.grey,
      ),
      onTap: onTap,
    );
  }
}