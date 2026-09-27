import 'package:flutter_test/flutter_test.dart';
import 'package:meu_app/screens/onboarding/onboarding_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('OnboardingStorage', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('primeiro acesso ainda não foi visto', () async {
      expect(await OnboardingStorage().isCompleted(), isFalse);
    });

    test('depois de concluir, fica marcado', () async {
      final storage = OnboardingStorage();
      await storage.markCompleted();
      expect(await storage.isCompleted(), isTrue);
    });

    test('reset faz o primeiro acesso aparecer de novo', () async {
      final storage = OnboardingStorage();
      await storage.markCompleted();
      await storage.reset();
      expect(await storage.isCompleted(), isFalse);
    });
  });
}
