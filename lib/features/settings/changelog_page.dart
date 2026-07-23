import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class ChangelogPage extends StatefulWidget {
  const ChangelogPage({super.key});

  @override
  State<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends State<ChangelogPage> {
  List<dynamic> _releases = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchReleases();
  }

  Future<void> _fetchReleases() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/delelimed/CatechHub/releases'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;
        setState(() {
          _releases = data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Errore nel recupero changelog (${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Errore di connessione: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Changelog'),
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 0,
      ),
      body: _buildBody(theme, isDark),
    );
  }

  Widget _buildBody(ThemeData theme, bool isDark) {
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }

    if (_error != null) {
      return _buildError(_error!, theme, isDark);
    }

    if (_releases.isEmpty) {
      return _buildEmpty(theme, isDark);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _releases.length,
      itemBuilder: (context, index) {
        final release = _releases[index] as Map<String, dynamic>;
        return _ReleaseCard(release: release, theme: theme, isDark: isDark);
      },
    );
  }

  Widget _buildError(String message, ThemeData theme, bool isDark) {
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Impossibile caricare',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _isLoading = true);
                _fetchReleases();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Riprova'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 64, color: isDark ? Colors.grey.shade600 : Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Nessun rilascio trovato',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  final Map<String, dynamic> release;
  final ThemeData theme;
  final bool isDark;

  const _ReleaseCard({
    required this.release,
    required this.theme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = theme.colorScheme;
    final version = release['tag_name'] as String? ?? 'Sconosciuta';
    final name = release['name'] as String? ?? '';
    final body = release['body'] as String? ?? 'Nessuna descrizione disponibile.';
    final publishedAt = release['published_at'] as String?;
    final prerelease = release['prerelease'] as bool? ?? false;
    final draft = release['draft'] as bool? ?? false;
    final htmlUrl = release['html_url'] as String? ?? '';

    final date = publishedAt != null
        ? DateFormat('dd MMMM yyyy', 'it_IT').format(DateTime.parse(publishedAt).toLocal())
        : 'Data sconosciuta';

    final cardColor = isDark ? colorScheme.surfaceContainer : Colors.white;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.3)
        : Colors.black.withValues(alpha: 0.04);
    final borderColor = isDark
        ? colorScheme.outline.withValues(alpha: 0.2)
        : Colors.grey.shade200;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: prerelease
                    ? [Colors.orange.shade400, Colors.deepOrange.shade500]
                    : draft
                        ? [Colors.grey.shade400, Colors.grey.shade600]
                        : [colorScheme.primary, colorScheme.secondary],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    version.replaceFirst('v', ''),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (name.isNotEmpty)
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(width: 10),
                Text(
                  date,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBody(body, theme, isDark),
                if (htmlUrl.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/webview', extra: {'url': htmlUrl}),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Visualizza su GitHub'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.primary,
                        side: BorderSide(color: colorScheme.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(String markdown, ThemeData theme, bool isDark) {
    final colorScheme = theme.colorScheme;
    final lines = markdown.split('\n');
    final widgets = <Widget>[];
    final textColor = isDark ? Colors.grey.shade300 : Colors.grey.shade800;
    final headingColor = isDark ? colorScheme.primary : const Color(0xFF174A7E);
    final mutedColor = isDark ? Colors.grey.shade500 : Colors.grey.shade700;
    final quoteBg = isDark ? colorScheme.primaryContainer.withValues(alpha: 0.3) : Colors.blue.shade50;
    final quoteBorder = isDark ? colorScheme.primary.withValues(alpha: 0.3) : Colors.blue.shade100;
    final quoteTextColor = isDark ? colorScheme.primary : Colors.blue.shade800;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      if (trimmed.startsWith('### ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(
            trimmed.substring(4),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: headingColor,
            ),
          ),
        ));
      } else if (trimmed.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            trimmed.substring(3),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: headingColor,
            ),
          ),
        ));
      } else if (trimmed.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            trimmed.substring(2),
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: headingColor,
            ),
          ),
        ));
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 16, top: 2, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• ', style: TextStyle(color: mutedColor, fontSize: 14)),
              Expanded(
                child: Text(
                  trimmed.substring(2),
                  style: TextStyle(color: textColor, fontSize: 14, height: 1.5),
                ),
              ),
            ],
          ),
        ));
      } else if (trimmed.startsWith('> ')) {
        widgets.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: quoteBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: quoteBorder),
          ),
          child: Text(
            trimmed.substring(2),
            style: TextStyle(color: quoteTextColor, fontSize: 13, fontStyle: FontStyle.italic),
          ),
        ));
      } else {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 2),
          child: Text(
            trimmed,
            style: TextStyle(color: textColor, fontSize: 14, height: 1.5),
          ),
        ));
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }
}