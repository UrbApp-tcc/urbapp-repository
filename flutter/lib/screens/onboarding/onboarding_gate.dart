import 'package:flutter/material.dart';

import '../../theme/urbapp_design.dart';
import 'onboarding_screen.dart';
import 'onboarding_storage.dart';

/// Mostra o primeiro acesso uma única vez e, depois, o [child]
/// (normalmente o AuthGate).
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key, required this.child});

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
      completed = await _storage.isCompleted();
    } catch (_) {
      // Se não der para ler o armazenamento, não trava o app.
      completed = true;
    }
    if (mounted) setState(() => _completed = completed);
  }

  Future<void> _finish() async {
    try {
      await _storage.markCompleted();
    } catch (_) {
      // Mesmo sem salvar, segue para o app.
    }
    if (mounted) setState(() => _completed = true);
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
