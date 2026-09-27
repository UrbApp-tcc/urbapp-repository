import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:meu_app/services/agency_service.dart';
import 'package:meu_app/services/post_service.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockAgencyService extends Mock implements AgencyService {}

// ── Helpers ──────────────────────────────────────────────────────────────────

PostService _makeService({
  MockSupabaseClient? supabase,
  MockAgencyService? agencyService,
}) =>
    PostService(
      supabase: supabase ?? MockSupabaseClient(),
      agencyService: agencyService ?? MockAgencyService(),
    );

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // toggleSupport — regras de negócio (validações antes de chegar ao banco)
  // ──────────────────────────────────────────────────────────────────────────
  group('PostService.toggleSupport — validações', () {
    late PostService service;

    setUp(() => service = _makeService());

    test('lança exceção quando usuário tenta apoiar o próprio reporte', () {
      expect(
        () => service.toggleSupport(
          postId: 1,
          currentUserId: 'user-abc',
          postAuthorId: 'user-abc',
          isCurrentlyLiked: false,
          postStatus: 'open',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'mensagem',
            contains('próprio reporte'),
          ),
        ),
      );
    });

    test('lança exceção para cada status final (completed, closed, expired)',
        () {
      for (final status in ['completed', 'closed', 'expired']) {
        expect(
          () => service.toggleSupport(
            postId: 1,
            currentUserId: 'user-abc',
            postAuthorId: 'user-xyz',
            isCurrentlyLiked: false,
            postStatus: status,
          ),
          throwsA(isA<Exception>()),
          reason: 'status "$status" deveria bloquear novas interações',
        );
      }
    });

    test('não lança regra de negócio para status não-finais', () async {
      // O mock não está configurado, então o erro virá do banco (não da validação).
      // O ponto é confirmar que a guarda de negócio não disparou.
      for (final status in ['open', 'in_progress', 'under_review']) {
        await expectLater(
          service.toggleSupport(
            postId: 1,
            currentUserId: 'user-abc',
            postAuthorId: 'user-xyz',
            isCurrentlyLiked: false,
            postStatus: status,
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'mensagem',
              isNot(anyOf(contains('próprio reporte'), contains('encerrado'))),
            ),
          ),
          reason: 'status "$status" não deveria ser bloqueado pelas regras de negócio',
        );
      }
    });

    test('auto-apoio é bloqueado mesmo quando postAuthorId não é null', () {
      const userId = 'same-user';
      expect(
        () => service.toggleSupport(
          postId: 42,
          currentUserId: userId,
          postAuthorId: userId,
          isCurrentlyLiked: true,
          postStatus: 'open',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('não bloqueia apoio quando postAuthorId é null (post anônimo)', () async {
      await expectLater(
        service.toggleSupport(
          postId: 1,
          currentUserId: 'user-abc',
          postAuthorId: null,
          isCurrentlyLiked: false,
          postStatus: 'open',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'mensagem',
            isNot(contains('próprio reporte')),
          ),
        ),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // resolvePost — regras de negócio
  // ──────────────────────────────────────────────────────────────────────────
  group('PostService.resolvePost — validações', () {
    late PostService service;

    setUp(() => service = _makeService());

    test('lança exceção para cada status final antes de chamar o banco', () async {
      for (final status in ['completed', 'closed', 'expired']) {
        await expectLater(
          service.resolvePost(
            postId: 1,
            userId: 'user-abc',
            fromStatus: status,
            note: 'alguma nota',
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'mensagem',
              contains('estado final'),
            ),
          ),
          reason: 'status "$status" não deveria permitir resolução',
        );
      }
    });

    test('não bloqueia statuses não-finais pela regra de status', () async {
      for (final status in ['open', 'in_progress']) {
        await expectLater(
          service.resolvePost(
            postId: 1,
            userId: 'user-abc',
            fromStatus: status,
            note: '',
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'mensagem',
              isNot(contains('estado final')),
            ),
          ),
          reason: 'status "$status" não deveria ser bloqueado pela guarda de status final',
        );
      }
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // PostComment.authorLabel — lógica de exibição do autor
  // ──────────────────────────────────────────────────────────────────────────
  group('PostComment.authorLabel', () {
    PostComment _comment({
      String displayName = '',
      String? username,
    }) =>
        PostComment(
          id: 1,
          postId: 1,
          userId: 'u',
          body: 'texto',
          createdAt: DateTime(2024),
          authorDisplayName: displayName,
          authorUsername: username,
        );

    test('exibe full_name quando preenchido', () {
      expect(_comment(displayName: 'Gabriel Alves').authorLabel, 'Gabriel Alves');
    });

    test('exibe username quando full_name está vazio', () {
      expect(_comment(displayName: '', username: 'gabriel').authorLabel, 'gabriel');
    });

    test('exibe "Usuario" quando ambos estão vazios', () {
      expect(_comment(displayName: '').authorLabel, 'Usuario');
    });

    test('ignora espaços em branco no full_name', () {
      expect(_comment(displayName: '   ').authorLabel, 'Usuario');
    });
  });
}
