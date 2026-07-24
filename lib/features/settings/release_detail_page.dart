import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class ReleaseDetailPage extends StatelessWidget {
  final Map<String, dynamic> release;

  const ReleaseDetailPage({super.key, required this.release});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final version = release['tag_name'] as String? ?? '';
    final name = release['name'] as String? ?? '';
    final body = release['body'] as String? ?? '';
    final publishedAt = release['published_at'] as String? ?? '';
    final prerelease = release['prerelease'] as bool? ?? false;
    final htmlUrl = release['html_url'] as String? ?? '';

    final date = publishedAt.isNotEmpty
        ? DateFormat(
            'dd MMMM yyyy',
            'it_IT',
          ).format(DateTime.parse(publishedAt).toLocal())
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text('Versione ${version.replaceFirst('v', '')}'),
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: prerelease
                    ? [Colors.orange.shade400, Colors.deepOrange.shade500]
                    : [colorScheme.primary, colorScheme.secondary],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        version.replaceFirst('v', ''),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    if (prerelease) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Pre-release',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (name.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (date != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    date,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? colorScheme.surfaceContainer : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? colorScheme.outline.withValues(alpha: 0.2)
                      : Colors.grey.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildMarkdownBody(body, theme, isDark),
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
                label: const Text('Visualizza su GitHub'),
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

  List<Widget> _buildMarkdownBody(
    String markdown,
    ThemeData theme,
    bool isDark,
  ) {
    final colorScheme = theme.colorScheme;
    final lines = markdown.split('\n');
    final widgets = <Widget>[];
    final textColor = isDark ? Colors.grey.shade300 : Colors.grey.shade800;
    final headingColor = isDark ? colorScheme.primary : const Color(0xFF174A7E);
    final mutedColor = isDark ? Colors.grey.shade500 : Colors.grey.shade700;
    final quoteBg = isDark
        ? colorScheme.primaryContainer.withValues(alpha: 0.3)
        : Colors.blue.shade50;
    final quoteBorder = isDark
        ? colorScheme.primary.withValues(alpha: 0.3)
        : Colors.blue.shade100;
    final quoteTextColor = isDark ? colorScheme.primary : Colors.blue.shade800;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      if (trimmed.startsWith('### ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(
              trimmed.substring(4),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: headingColor,
              ),
            ),
          ),
        );
      } else if (trimmed.startsWith('## ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              trimmed.substring(3),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: headingColor,
              ),
            ),
          ),
        );
      } else if (trimmed.startsWith('# ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              trimmed.substring(2),
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: headingColor,
              ),
            ),
          ),
        );
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 2, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: TextStyle(color: mutedColor, fontSize: 14)),
                Expanded(
                  child: Text(
                    trimmed.substring(2),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (trimmed.startsWith('> ')) {
        widgets.add(
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: quoteBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: quoteBorder),
            ),
            child: Text(
              trimmed.substring(2),
              style: TextStyle(
                color: quoteTextColor,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        );
      } else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: Text(
              trimmed,
              style: TextStyle(color: textColor, fontSize: 14, height: 1.5),
            ),
          ),
        );
      }
    }

    return widgets;
  }
}
