import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
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
  int _page = 1;
  final int _perPage = 30;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();

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
    if (loadMore) {
      _page++;
    } else {
      _page = 1;
      _commits = [];
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.get(
        Uri.parse(
          'https://api.github.com/repos/delelimed/CatechHub/commits?per_page=$_perPage&page=$_page',
        ),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;
        setState(() {
          if (loadMore) {
            _commits.addAll(data);
          } else {
            _commits = data;
          }
          _hasMore = data.length == _perPage;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Errore nel recupero commits (${response.statusCode})';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Commits recenti'),
        backgroundColor: const Color(0xFF174A7E),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _fetchCommits(),
            tooltip: 'Aggiorna',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _commits.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _commits.isEmpty) {
      return _buildError(_error!);
    }

    if (_commits.isEmpty) {
      return _buildEmpty();
    }

    return RefreshIndicator(
      onRefresh: () => _fetchCommits(),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _commits.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _commits.length) {
            return _buildLoadMore();
          }
          final commit = _commits[index] as Map<String, dynamic>;
          return _CommitCard(commit: commit);
        },
      ),
    );
  }

  Widget _buildLoadMore() {
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
                foregroundColor: const Color(0xFF174A7E),
              ),
            ),
          );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(
              'Impossibile caricare',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _fetchCommits(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Riprova'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF174A7E),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.source_rounded, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Nessun commit trovato',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommitCard extends StatelessWidget {
  final Map<String, dynamic> commit;

  const _CommitCard({required this.commit});

  @override
  Widget build(BuildContext context) {
    final commitData = commit['commit'] as Map<String, dynamic>;
    final author = commitData['author'] as Map<String, dynamic>;
    final committer = commitData['committer'] as Map<String, dynamic>;
    final message = commitData['message'] as String? ?? 'Nessun messaggio';
    final date = committer['date'] as String? ?? author['date'] as String?;
    final sha = commit['sha'] as String? ?? '';
    final htmlUrl = commit['html_url'] as String? ?? '';
    final authorName = author['name'] as String? ?? 'Sconosciuto';
    final authorLogin = commit['author']?['login'] as String? ?? '';
    final authorAvatar = commit['author']?['avatar_url'] as String? ?? '';

    final shortSha = sha.length >= 7 ? sha.substring(0, 7) : sha;
    final firstLine = message.split('\n').first;
    final remainingLines = message.split('\n').skip(1).join('\n');

    final formattedDate = date != null
        ? DateFormat('dd MMM yyyy, HH:mm', 'it_IT').format(DateTime.parse(date).toLocal())
        : 'Data sconosciuta';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: htmlUrl.isNotEmpty
            ? () => context.push('/webview', extra: {'url': htmlUrl})
            : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (authorAvatar.isNotEmpty)
                    CircleAvatar(
                      radius: 18,
                      backgroundImage: NetworkImage(authorAvatar),
                      backgroundColor: Colors.grey.shade200,
                    )
                  else
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF174A7E).withValues(alpha: 0.1),
                      child: Text(
                        authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Color(0xFF174A7E),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          authorLogin.isNotEmpty ? '@$authorLogin' : authorName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Color(0xFF174A7E),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          formattedDate,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      shortSha,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF174A7E),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                firstLine,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade800,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (remainingLines.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    remainingLines,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      height: 1.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
              if (htmlUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/webview', extra: {'url': htmlUrl}),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Visualizza su GitHub'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF174A7E),
                      side: const BorderSide(color: Color(0xFF174A7E)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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