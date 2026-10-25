import 'package:flutter_test/flutter_test.dart';
import 'package:meu_app/app/institutional_intent.dart';
import 'package:meu_app/domain/labels.dart';
import 'package:meu_app/domain/models.dart';
import 'package:meu_app/domain/occurrence_status.dart';
import 'package:meu_app/screens/report/report_flow_screen.dart';
import 'package:meu_app/services/ranking_service.dart';
import 'package:meu_app/utils/date_formatter.dart';
import 'package:meu_app/utils/error_formatter.dart';

void main() {
  group('OccurrenceStatus', () {
    test(
      'mapeia os códigos do banco para os estados oficiais da especificação',
      () {
        expect(OccurrenceStatus.fromCode('open').label, 'Aberto');
        expect(OccurrenceStatus.fromCode('in_analysis').label, 'Em análise');
        expect(OccurrenceStatus.fromCode('in_progress').label, 'Em andamento');
        expect(
          OccurrenceStatus.fromCode('awaiting_validation').label,
          'Aguardando validação',
        );
        expect(OccurrenceStatus.fromCode('completed').label, 'Resolvido');
        expect(OccurrenceStatus.fromCode('reopened').label, 'Reaberto');
        expect(OccurrenceStatus.fromCode('closed').label, 'Encerrado');
      },
    );

    test('o valor legado expired não existe como estado do app', () {
      expect(
        OccurrenceStatus.values.map((status) => status.code),
        isNot(contains('expired')),
      );
      expect(OccurrenceStatus.fromCode('expired'), OccurrenceStatus.open);
    });

    test('encerrado nunca é tratado como resolvido', () {
      expect(OccurrenceStatus.closed.isFinal, isTrue);
      expect(OccurrenceStatus.closed == OccurrenceStatus.resolved, isFalse);
      expect(OccurrenceStatus.closed.lifecycleIndex, -1);
    });

    test('apenas estados operacionais aceitam informar possível resolução', () {
      final accepting = OccurrenceStatus.values
          .where((status) => status.acceptsResolutionReport)
          .toSet();
      expect(accepting, {
        OccurrenceStatus.open,
        OccurrenceStatus.inAnalysis,
        OccurrenceStatus.inProgress,
        OccurrenceStatus.reopened,
      });
    });

    test(
      'a trilha do ciclo segue ABERTO → EM_ANALISE → EM_ANDAMENTO → AGUARDANDO → RESOLVIDO',
      () {
        expect(
          OccurrenceStatus.lifecycle.map((status) => status.code).toList(),
          [
            'open',
            'in_analysis',
            'in_progress',
            'awaiting_validation',
            'completed',
          ],
        );
        expect(OccurrenceStatus.reopened.lifecycleIndex, 0);
      },
    );
  });

  group('Occurrence.fromJson', () {
    Map<String, dynamic> row({Map<String, dynamic> extra = const {}}) => {
      'id': 7,
      'title': 'Buraco perigoso',
      'summary': 'Descrição',
      'status': 'in_progress',
      'created_at': '2026-10-01T10:00:00Z',
      'latitude': -23.5,
      'longitude': -47.4,
      'city_id': 1,
      'city_name': 'Sorocaba',
      'category_id': 2,
      'category_name': 'Vias públicas',
      'agency_id': 3,
      'agency_name': 'Secretaria de Obras',
      'agency_profile_status': 'participant',
      'administration_id': 4,
      'reports_count': 3,
      'supports_count': 12,
      'recent_supports_count': 2,
      'comments_count': 5,
      'supported_by_me': true,
      'latest_official_action': {
        'actor_kind': 'agency',
        'action_type': 'scheduled',
        'description': 'Serviço programado',
        'created_at': '2026-10-02T10:00:00Z',
        'agency_name': 'Secretaria de Obras',
        'agency_profile_status': 'participant',
      },
      ...extra,
    };

    test('lê contadores derivados e o vínculo institucional', () {
      final occurrence = Occurrence.fromJson(row());
      expect(occurrence.status, OccurrenceStatus.inProgress);
      expect(occurrence.reportsCount, 3);
      expect(occurrence.supportsCount, 12);
      expect(occurrence.agencyStatus, InstitutionalProfileStatus.participant);
      expect(occurrence.agencyStatus.isVerified, isTrue);
      expect(
        occurrence.latestOfficialAction?.actorLabel,
        'Secretaria de Obras',
      );
      expect(occurrence.trendLabel, '+2 apoios hoje');
      expect(occurrence.isMunicipal, isTrue);
    });

    test('perfil institucional sem status explícito é não reivindicado', () {
      final occurrence = Occurrence.fromJson(
        row(extra: {'agency_profile_status': null}),
      );
      expect(occurrence.agencyStatus, InstitutionalProfileStatus.unclaimed);
      expect(occurrence.agencyStatus.label, 'Não reivindicado');
    });

    test('apoio otimista atualiza contagem e estado', () {
      final occurrence = Occurrence.fromJson(row());
      final next = occurrence.copyWith(supportedByMe: false, supportsCount: 11);
      expect(next.supportedByMe, isFalse);
      expect(next.supportsCount, 11);
      expect(next.title, occurrence.title);
    });
  });

  group('ResolutionContext', () {
    test(
      'o contexto do backend informa voto já registrado e quórum do ciclo',
      () {
        final context = ResolutionContext.fromJson({
          'can_start': false,
          'evidence_required': true,
          'settings': {
            'confirmations_required': 3,
            'rejections_required': 2,
            'radius_km': 5,
            'duration_hours': 72,
            'cooldown_hours': 24,
          },
          'cycle': {
            'id': 10,
            'initiator_kind': 'agency',
            'initiated_by_me': false,
            'opened_at': '2026-10-01T10:00:00Z',
            'expires_at': '2099-10-04T10:00:00Z',
            'confirmations': 2,
            'rejections': 0,
            'confirmations_required': 3,
            'rejections_required': 2,
            'radius_km': 5,
            'my_vote': 'confirm',
          },
        });
        expect(context.cycle?.myVote, 'confirm');
        expect(context.cycle?.initiatorLabel, 'O órgão responsável');
        expect(context.confirmationsRequired, 3);
        expect(context.evidenceRequired, isTrue);
        expect(context.cycle!.remaining.inHours, greaterThan(0));
      },
    );
  });

  group('AppNotification', () {
    test('identifica alertas de validação e atualizações oficiais', () {
      final notification = AppNotification.fromJson({
        'id': 1,
        'type': 'occurrence_event',
        'title': 'Validação comunitária disponível',
        'body': '...',
        'created_at': '2026-10-01T10:00:00Z',
        'read_at': null,
        'payload': {
          'occurrence_id': 9,
          'event_type': 'validation_opened',
          'actor_kind': 'citizen',
        },
      });
      expect(notification.isValidation, isTrue);
      expect(notification.isOfficial, isFalse);
      expect(notification.read, isFalse);
      expect(notification.markRead().read, isTrue);
    });

    test('preserva os detalhes de um contato institucional', () {
      final notification = AppNotification.fromJson({
        'id': 2,
        'type': 'administration_contact',
        'title': 'Credenciar a Prefeitura',
        'body': 'Precisamos concluir o credenciamento institucional.',
        'created_at': '2026-10-24T18:30:00Z',
        'read_at': null,
        'payload': {
          'contact_kind_label': 'Credenciamento institucional',
          'administration_name': 'Gestão 2025–2028',
          'requester_name': 'Gestão Sorocaba',
          'requester_username': 'prefeitura.sorocaba',
          'requester_badge_name': 'Cidadão Presente',
          'requester_level': 2,
          'request_subject': 'Credenciar a Prefeitura',
          'request_message':
              'Precisamos concluir o credenciamento institucional.',
        },
      });

      expect(notification.isAdministrationContact, isTrue);
      expect(notification.contactRequesterUsername, 'prefeitura.sorocaba');
      expect(notification.contactRequesterLevel, 2);
      expect(notification.markRead().contactRequesterBadge, 'Cidadão Presente');
    });
  });

  group('Formatação', () {
    final now = DateTime(2026, 10, 4, 12);

    test('tempo relativo em português', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(seconds: 10)), now: now),
        'Agora',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 5)), now: now),
        'Há 5 min',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 3)), now: now),
        'Há 3 h',
      );
      expect(formatRelativeTime(DateTime(2026, 10, 3, 18), now: now), 'Ontem');
    });

    test('datas da linha do tempo', () {
      expect(
        formatTimelineDate(DateTime(2026, 10, 4, 9, 42), now: now),
        'Hoje, 09:42',
      );
      expect(
        formatTimelineDate(DateTime(2026, 10, 3, 18, 20), now: now),
        'Ontem, 18:20',
      );
      expect(
        formatTimelineDate(DateTime(2026, 10, 1, 14, 10), now: now),
        '01/10, 14:10',
      );
    });

    test('agrupamento de alertas', () {
      expect(alertGroupOf(DateTime(2026, 10, 4, 1), now: now), 'Hoje');
      expect(alertGroupOf(DateTime(2026, 10, 3), now: now), 'Ontem');
      expect(alertGroupOf(DateTime(2026, 9, 30), now: now), 'Esta semana');
      expect(alertGroupOf(DateTime(2026, 9, 1), now: now), 'Anteriores');
    });

    test('números, distâncias e dias', () {
      expect(formatCount(1523), '1.523');
      expect(formatDistance(0.85), '850 m');
      expect(formatDistance(2.4), '2,4 km');
      expect(formatDays(8.4 * 86400), '8,4');
      expect(formatDays(null), '—');
    });
  });

  group('Mensagens do backend', () {
    test('regras de negócio aparecem com grafia correta', () {
      expect(
        friendlyBackendMessage(
          'Quem iniciou o ciclo nao pode votar nele.',
          'fallback',
        ),
        'Quem informou a possível resolução não participa da contagem deste ciclo.',
      );
      expect(
        friendlyBackendMessage(
          'Usuario fora do raio permitido para validacao.',
          'fallback',
        ),
        contains('próximo ao local'),
      );
      expect(
        friendlyBackendMessage(
          'Usuário fora do raio permitido para validação.',
          'fallback',
        ),
        contains('próximo ao local'),
      );
    });

    test('erros técnicos não vazam para o usuário', () {
      expect(
        friendlyBackendMessage(
          'new row violates row-level security policy',
          'fallback',
        ),
        'Você não tem permissão para esta ação.',
      );
      expect(
        friendlyBackendMessage('column "x" does not exist', 'fallback'),
        'fallback',
      );
    });
  });

  group('Ações institucionais', () {
    test('o vereador nunca é rotulado como responsável pela resolução', () {
      final labels = [
        ...councilorActionLabels.values,
        ...councilorFollowingStatusLabels.values,
      ].join(' ').toLowerCase();
      expect(labels, isNot(contains('resolvido pelo')));
      expect(
        councilorFollowingStatusLabels['resolved'],
        'Resolvida durante o acompanhamento',
      );
    });

    test('órgão pode confirmar recebimento e informar conclusão', () {
      expect(institutionalActionLabels['received'], 'Recebimento confirmado');
      expect(institutionalActionLabels['conclusion'], 'Conclusão informada');
    });
  });

  group('Rankings', () {
    test('a posição pessoal indica quando o perfil fica fora do ranking', () {
      final standing = ParticipationStanding.fromJson({
        'points': 145,
        'participants': 4,
        'position': null,
        'points_to_next': null,
        'eligible': false,
        'reason': 'private',
      });
      expect(standing.eligible, isFalse);
      expect(standing.reason, 'private');
      expect(standing.position, isNull);
    });

    test('os períodos do ranking seguem os códigos do backend', () {
      expect(RankingPeriod.values.map((period) => period.code), [
        'month',
        'all',
      ]);
      expect(RankingPeriod.month.label, 'Este mês');
      expect(RankingPeriod.all.label, 'Geral');
    });
  });

  group('Acesso institucional', () {
    test('os papéis solicitáveis seguem os códigos do backend', () {
      expect(
        InstitutionalKind.fromCode('councilor'),
        InstitutionalKind.councilor,
      );
      expect(InstitutionalKind.fromCode('agency'), InstitutionalKind.agency);
      expect(
        InstitutionalKind.fromCode('administration'),
        InstitutionalKind.administration,
      );
      expect(InstitutionalKind.fromCode('mayor'), isNull);
      expect(InstitutionalKind.fromCode(null), isNull);
    });
  });

  group('Ranking de cidades', () {
    test(
      'indicadores objetivos seguem os códigos do backend, sem score composto',
      () {
        expect(CityIndicator.values.map((indicator) => indicator.code), [
          'resolution_rate',
          'resolution_time',
        ]);
      },
    );

    test('cidade classificada traz posição, taxa e mediana', () {
      final row = CityRankingRow.fromJson({
        'rank_position': 1,
        'city_id': 5,
        'city_name': 'Alumínio',
        'state': 'sp',
        'eligible_occurrences': 200,
        'resolved_occurrences': 148,
        'resolution_rate': 74.0,
        'median_resolution_seconds': 5.8 * 86400,
        'qualified': true,
        'minimum_required': 10,
      });
      expect(row.position, 1);
      expect(row.stateCode, 'SP');
      expect(row.resolved / row.eligible, closeTo(0.74, 0.001));
      expect(row.qualified, isTrue);
    });

    test('cidade abaixo da amostra mínima não tem posição', () {
      final row = CityRankingRow.fromJson({
        'rank_position': null,
        'city_id': 7,
        'city_name': 'Cidade Pequena',
        'state': 'mg',
        'eligible_occurrences': 1,
        'resolved_occurrences': 1,
        'resolution_rate': 100.0,
        'median_resolution_seconds': null,
        'qualified': false,
        'minimum_required': 10,
      });
      expect(row.position, isNull);
      expect(row.qualified, isFalse);
      expect(row.minimumRequired, 10);
    });
  });

  group('Título sugerido do relato', () {
    test('usa a primeira frase da descrição, com inicial maiúscula', () {
      expect(
        suggestReportTitle(
          'o semáforo fica piscando amarelo há dias. Já houve quase acidente.',
        ),
        'O semáforo fica piscando amarelo há dias',
      );
    });

    test('corta em uma palavra inteira quando a frase é longa', () {
      final title = suggestReportTitle(
        'Existe um buraco muito grande e profundo no meio da rua principal do bairro que atrapalha todos',
      );
      expect(title.length, lessThanOrEqualTo(60));
      expect(title.endsWith(' '), isFalse);
      expect(title, startsWith('Existe um buraco muito grande'));
    });

    test('descrição vazia não gera título', () {
      expect(suggestReportTitle('   '), '');
    });
  });
}
