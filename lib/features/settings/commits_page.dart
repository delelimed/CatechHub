import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

class CommitsPage extends StatefulWidget {
  const CommitsPage({super.key});

  @override
  State<CommitsPage> createState() => _CommitsPageState();
}

class _CommitsPageState extends State<CommitsPage> {
  List<dynamic> _commits = [];
  bool _isLoading = true;
  String? _error;
  bool _hasMore = true;
  String? _nextPageUrl;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchCommits();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _fetchCommits(loadMore: true);
    }
  }

  Future<void> _fetchCommits({bool loadMore = false}) async {
    if (loadMore && _isLoading) return;
    if (loadMore && _nextPageUrl == null) return;

    if (!loadMore) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    } else {
      setState(() => _isLoading = true);
    }

    try {
      final url = _nextPageUrl ??
          'https://api.github.com/repos/delelimed/CatechHub/commits?per_page=30';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;

        final linkHeader = response.headers['link'];
        String? nextUrl;
        if (linkHeader != null) {
          final matches = RegExp(r'<([^>]+)>;\s*rel="next"').allMatches(linkHeader);
          if (matches.isNotEmpty) {
            nextUrl = matches.first.group(1);
          }
        }

        setState(() {
          if (loadMore) {
            _commits.addAll(data);
          } else {
            _commits = data;
          }
          _nextPageUrl = nextUrl;
          _hasMore = nextUrl != null;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Errore nel recupero commit (${response.statusCode})';
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
        title: const Text('Commits recenti'),
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _fetchCommits(),
            tooltip: 'Aggiorna',
          ),
        ],
      ),
      body: _buildBody(theme, isDark),
    );
  }

  Widget _buildBody(ThemeData theme, bool isDark) {
    final colorScheme = theme.colorScheme;

    if (_isLoading && _commits.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }

    if (_error != null && _commits.isEmpty) {
      return _buildError(_error!, theme, isDark);
    }

    if (_commits.isEmpty) {
      return _buildEmpty(theme, isDark);
    }

    return RefreshIndicator(
      onRefresh: () => _fetchCommits(),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _commits.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _commits.length) {
            return _buildLoadMore(theme, isDark);
          }
          final commit = _commits[index] as Map<String, dynamic>;
          return _CommitCard(commit: commit, theme: theme, isDark: isDark);
        },
      ),
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
              onPressed: () => _fetchCommits(),
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
              'Nessun commit trovato',
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

  Widget _buildLoadMore(ThemeData theme, bool isDark) {
    return _isLoading
        ? const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        : Padding(
            padding: const EdgeInsets.all(16),
            child: TextButton.icon(
              onPressed: () => _fetchCommits(loadMore: true),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Carica altro'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
              ),
            ),
          );
  }
}

class _CommitCard extends StatelessWidget {
  final Map<String, dynamic> commit;
  final ThemeData theme;
  final bool isDark;

  const _CommitCard({
    required this.commit,
    required this.theme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = theme.colorScheme;
    final sha = commit['sha'] as String? ?? '';
    final message = commit['commit']?['message'] as String? ?? 'Nessun messaggio';
    final author = commit['commit']?['author']?['name'] as String? ?? 'Sconosciuto';
    final dateStr = commit['commit']?['author']?['date'] as String?;
    final htmlUrl = commit['html_url'] as String? ?? '';

    final shortSha = sha.length >= 7 ? sha.substring(0, 7) : sha;
    final date = dateStr != null
        ? DateFormat('dd MMM yyyy HH:mm', 'it_IT').format(DateTime.parse(dateStr).toLocal())
        : 'Data sconosciuta';

    final cardColor = isDark ? colorScheme.surfaceContainer : Colors.white;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.3)
        : Colors.black.withValues(alpha: 0.04);
    final borderColor = isDark
        ? colorScheme.outline.withValues(alpha: 0.2)
        : Colors.grey.shade200;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: htmlUrl.isNotEmpty ? () => context.push('/webview', extra: {'url': htmlUrl}) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      shortSha,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message.split('\n').first,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.person_outline_rounded, size: 14, color: isDark ? Colors.grey.shade500 : Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    author,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.access_time_rounded, size: 14, color: isDark ? Colors.grey.shade500 : Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    date,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              if (htmlUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/webview', extra: {'url': htmlUrl}),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Visualizza'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                      side: BorderSide(color: colorScheme.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}