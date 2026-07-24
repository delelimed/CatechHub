import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class CommitDetailPage extends StatelessWidget {
  final Map<String, dynamic> commit;

  const CommitDetailPage({super.key, required this.commit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final sha = commit['sha'] as String? ?? '';
    final commitData = commit['commit'] as Map<String, dynamic>? ?? {};
    final message = commitData['message'] as String? ?? '';
    final authorData = commitData['author'] as Map<String, dynamic>? ?? {};
    final committerData =
        commitData['committer'] as Map<String, dynamic>? ?? {};
    final authorName = authorData['name'] as String? ?? '';
    final authorEmail = authorData['email'] as String? ?? '';
    final authorDateStr = authorData['date'] as String? ?? '';
    final committerName = committerData['name'] as String? ?? '';
    final committerEmail = committerData['email'] as String? ?? '';
    final htmlUrl = commit['html_url'] as String? ?? '';

    final dateStr = authorDateStr.isNotEmpty
        ? DateFormat(
            'dd MMMM yyyy HH:mm',
            'it_IT',
          ).format(DateTime.parse(authorDateStr).toLocal())
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dettaglio commit'),
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.content_copy_rounded),
            tooltip: 'Copia SHA',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: sha));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('SHA copiato')));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            title: 'SHA',
            icon: Icons.fingerprint,
            theme: theme,
            child: SelectableText(
              sha,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Autore',
            icon: Icons.person,
            theme: theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (authorName.isNotEmpty)
                  Text(
                    authorName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                if (authorEmail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    authorEmail,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
                if (dateStr != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        dateStr,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (committerName.isNotEmpty &&
              (committerName != authorName ||
                  committerEmail != authorEmail)) ...[
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Committer',
              icon: Icons.person_outline,
              theme: theme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (committerName.isNotEmpty)
                    Text(
                      committerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  if (committerEmail.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      committerEmail,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (message.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Messaggio',
              icon: Icons.message,
              theme: theme,
              child: SelectableText(
                message,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
          ],
          if (htmlUrl.isNotEmpty) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  if (await canLaunchUrl(Uri.parse(htmlUrl))) {
                    await launchUrl(
                      Uri.parse(htmlUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Apri su GitHub'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  side: BorderSide(color: colorScheme.primary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final IconData icon;
  final ThemeData theme;

  const _SectionCard({
    required this.title,
    required this.child,
    required this.icon,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainer : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? colorScheme.outline.withValues(alpha: 0.2)
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
