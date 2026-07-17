import 'package:flutter/material.dart';

class PhaseBanner extends StatelessWidget {
  final String message;

  const PhaseBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF174A7E).withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(color: const Color(0xFF174A7E).withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: const Color(0xFF174A7E),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF174A7E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
