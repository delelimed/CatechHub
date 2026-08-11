import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/user_role.dart';
import 'demo_guide_service.dart';
import 'guide_steps.dart';

class GuidePage extends ConsumerStatefulWidget {
  const GuidePage({super.key, this.reviewMode = false});

  final bool reviewMode;

  @override
  ConsumerState<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends ConsumerState<GuidePage> {
  late final PageController _pageController;
  late final List<GuideStep> _steps;
  int _currentIndex = 0;
  bool _seeding = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _steps = UserRole.isResponsabile
        ? responsabileGuideSteps()
        : catechistGuideSteps();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _seedDemoDataIfNeeded();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _seedDemoDataIfNeeded() async {
    if (widget.reviewMode) return;
    if (!DemoGuideService.isGuidePending()) return;
    if (_seeding) return;
    _seeding = true;
    try {
      await DemoGuideService.seedGuideData(
        isResponsabile: UserRole.isResponsabile,
      );
    } catch (_) {}
    if (mounted) setState(() {});
  }

  bool get _isLastStep => _currentIndex == _steps.length - 1;

  void _goNext() {
    if (_isLastStep) return;
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _finishGuide() async {
    if (widget.reviewMode) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await DemoGuideService.completeGuide();
    if (!mounted) return;
    if (UserRole.isResponsabile) {
      context.go('/parrocchia');
    } else {
      context.go('/');
    }
  }

  void _tryFeature(String route) {
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final primary = isDark ? colorScheme.primary : const Color(0xFF174A7E);

    return PopScope(
      canPop: widget.reviewMode,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: _ProgressBar(
                        currentIndex: _currentIndex,
                        total: _steps.length,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _steps.length,
                  onPageChanged: (index) => setState(() => _currentIndex = index),
                  itemBuilder: (context, index) {
                    return _GuideStepView(
                      step: _steps[index],
                      isDark: isDark,
                      colorScheme: colorScheme,
                      onTry: _steps[index].demoRoute == null
                          ? null
                          : () => _tryFeature(_steps[index].demoRoute!),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _isLastStep
                          ? _GuideButton(
                              label: widget.reviewMode
                                  ? 'Chiudi guida'
                                  : 'Comincia a usare l\'app',
                              icon: Icons.rocket_launch_rounded,
                              primary: primary,
                              onPressed: _finishGuide,
                            )
                          : _GuideButton(
                              label: 'Avanti',
                              icon: Icons.arrow_forward_rounded,
                              primary: primary,
                              onPressed: _goNext,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int currentIndex;
  final int total;

  const _ProgressBar({required this.currentIndex, required this.total});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.primary
        : const Color(0xFF174A7E);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(
        value: (currentIndex + 1) / total,
        minHeight: 8,
        backgroundColor: Colors.grey.shade300,
        valueColor: AlwaysStoppedAnimation<Color>(primary),
      ),
    );
  }
}

class _GuideStepView extends StatelessWidget {
  final GuideStep step;
  final bool isDark;
  final ColorScheme colorScheme;
  final VoidCallback? onTry;

  const _GuideStepView({
    required this.step,
    required this.isDark,
    required this.colorScheme,
    this.onTry,
  });

  @override
  Widget build(BuildContext context) {
    final primary = isDark ? colorScheme.primary : const Color(0xFF174A7E);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Icon(step.icon, size: 52, color: primary),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                step.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? colorScheme.onSurface : const Color(0xFF174A7E),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                step.description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                ),
              ),
              if (onTry != null) ...[
                const SizedBox(height: 28),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: onTry,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primary,
                      side: BorderSide(color: primary.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text(
                      'Prova questa funzione',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Torna indietro quando hai finito di provare.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
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

class _GuideButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color primary;
  final VoidCallback onPressed;

  const _GuideButton({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: Icon(icon, size: 22),
        label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
