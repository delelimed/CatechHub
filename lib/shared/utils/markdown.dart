import 'package:flutter/material.dart';

TextSpan _buildTextSpan(String text, TextStyle? baseStyle) {
  final style = baseStyle ?? const TextStyle();
  final spans = <TextSpan>[];
  final bold = RegExp(r'\*\*(.+?)\*\*');
  final italic = RegExp(r'\*(.+?)\*');
  final code = RegExp(r'`(.+?)`');

  int i = 0;
  while (i < text.length) {
    final boldMatch = bold.matchAsPrefix(text, i);
    final italicMatch = italic.matchAsPrefix(text, i);
    final codeMatch = code.matchAsPrefix(text, i);

    int? earliest = boldMatch?.start;
    String? type;
    Match? match;

    if (boldMatch != null &&
        (earliest == null || boldMatch.start <= earliest)) {
      earliest = boldMatch.start;
      type = 'bold';
      match = boldMatch;
    }
    if (italicMatch != null &&
        (earliest == null || italicMatch.start < earliest)) {
      earliest = italicMatch.start;
      type = 'italic';
      match = italicMatch;
    }
    if (codeMatch != null && (earliest == null || codeMatch.start < earliest)) {
      earliest = codeMatch.start;
      type = 'code';
      match = codeMatch;
    }

    if (match != null && type != null) {
      if (match.start > i) {
        spans.add(TextSpan(text: text.substring(i, match.start)));
      }
      switch (type) {
        case 'bold':
          spans.add(
            TextSpan(
              text: match.group(1),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        case 'italic':
          spans.add(
            TextSpan(
              text: match.group(1),
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          );
        case 'code':
          spans.add(
            TextSpan(
              text: match.group(1),
              style: TextStyle(
                fontFamily: 'monospace',
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
              ),
            ),
          );
      }
      i = match.end;
    } else {
      spans.add(TextSpan(text: text.substring(i)));
      break;
    }
  }

  return TextSpan(style: style, children: spans);
}

Widget buildMarkdownText(String text, TextStyle? style) {
  return Text.rich(_buildTextSpan(text, style));
}

Widget buildSelectableMarkdownText(String text, TextStyle? style) {
  return SelectableText.rich(_buildTextSpan(text, style));
}
