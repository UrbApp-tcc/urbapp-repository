import 'package:flutter/material.dart';

import '../../theme/urbapp_design.dart';
import 'onboarding_screen.dart';
import 'onboarding_storage.dart';

/// Depois do login, mostra o primeiro acesso uma única vez por usuário
/// e, depois, o [child] (a tela principal do app).
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({
    super.key,
    required this.userId,
    required this.metadata,
    required this.child,
  });

  final String userId;
  final Map<String, dynamic>? metadata;
  final Widget child;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  final _storage = OnboardingStorage();
  bool? _completed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    bool completed;
    try {
      completed = await _storage.isCompleted(
        userId: widget.userId,
        metadata: widget.metadata,
      );
    } catch (_) {
      // Se não der para verificar, não trava o app.
      completed = true;
    }
    if (mounted) setState(() => _completed = completed);
  }

  Future<void> _finish() async {
    if (mounted) setState(() => _completed = true);
    try {
      await _storage.markCompleted(userId: widget.userId);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final completed = _completed;

    if (completed == null) {
      // Mesma cor do primeiro acesso, para não piscar branco.
      return const Scaffold(backgroundColor: UrbColors.hero);
    }

    return AnimatedSwitcher(
      duration: UrbMotion.of(context, UrbMotion.medium),
      child: completed
          ? KeyedSubtree(key: const ValueKey('app'), child: widget.child)
          : OnboardingScreen(
              key: const ValueKey('onboarding'),
              onFinished: _finish,
            ),
    );
  }
}
