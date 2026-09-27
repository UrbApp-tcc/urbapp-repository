import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../widgets/gamification_listener.dart';
import '../app_shell_screen.dart';
import '../onboarding/onboarding_gate.dart';
import 'login_screen.dart';
import 'reset_password_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _authService.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.data?.event == AuthChangeEvent.passwordRecovery) {
          return const ResetPasswordScreen();
        }

        final session = snapshot.data?.session ?? _authService.currentSession;

        if (snapshot.connectionState == ConnectionState.waiting &&
            session == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (session == null) {
          return const LoginScreen();
        }

        final user = session.user;

        // Primeiro acesso: aparece só na primeira vez que o usuário entra.
        // A key com o id recria tudo ao trocar de conta.
        return OnboardingGate(
          key: ValueKey('onboarding-${user.id}'),
          userId: user.id,
          metadata: user.userMetadata,
          child: GamificationListener(
            key: ValueKey(user.id),
            child: const AppShellScreen(),
          ),
        );
      },
    );
  }
}
