import 'package:flutter_test/flutter_test.dart';
import 'package:meu_app/screens/onboarding/onboarding_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('onboardingDoneInMetadata', () {
    test('sem metadados, ainda não viu', () {
      expect(onboardingDoneInMetadata(null), isFalse);
      expect(onboardingDoneInMetadata({}), isFalse);
    });

    test('com a marcação na conta, já viu', () {
      expect(onboardingDoneInMetadata({onboardingMetadataKey: true}), isTrue);
    });

    test('marcação desfeita conta como não visto', () {
      expect(onboardingDoneInMetadata({onboardingMetadataKey: false}), isFalse);
    });
  });

  group('OnboardingStorage', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('usuário novo ainda não viu o primeiro acesso', () async {
      expect(await OnboardingStorage().isCompleted(userId: 'u1'), isFalse);
    });

    test('marcar como visto vale só para aquele usuário', () async {
      final storage = OnboardingStorage();
      await storage.markCompleted(userId: 'u1');

      expect(await storage.isCompleted(userId: 'u1'), isTrue);
      expect(await storage.isCompleted(userId: 'u2'), isFalse);
    });

    test('metadados da conta bastam, mesmo em outro aparelho', () async {
      final storage = OnboardingStorage();
      expect(
        await storage.isCompleted(
          userId: 'u1',
          metadata: {onboardingMetadataKey: true},
        ),
        isTrue,
      );
    });
  });
}
