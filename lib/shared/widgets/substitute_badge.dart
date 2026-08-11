import 'package:flutter/material.dart';

/// Badge visivo **[SUPPLENZA]** mostrato accanto alle classi delegata
/// temporaneamente al Supplente.
class SubstituteBadge extends StatelessWidget {
  final bool compact;

  const SubstituteBadge({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: Colors.deepOrange.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.deepOrange.shade400),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.swap_horiz_rounded,
              size: compact ? 12 : 14, color: Colors.deepOrange.shade800),
          const SizedBox(width: 4),
          Text(
            'SUPPLENZA',
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: Colors.deepOrange.shade800,
            ),
          ),
        ],
      ),
    );
  }
}