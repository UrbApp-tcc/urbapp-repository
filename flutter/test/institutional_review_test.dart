import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:meu_app/domain/models.dart';
import 'package:meu_app/logic/institutional_review_rules.dart';
import 'package:meu_app/screens/admin/institutional_verification_screen.dart';
import 'package:meu_app/services/institutional_service.dart';
import 'package:meu_app/services/notifications_service.dart';
import 'package:meu_app/theme/app_theme.dart';

Map<String, dynamic> _row({String status = 'pending', String type = 'councilor'}) => {
      'request_type': type,
      'request_id': 7,
      'status': status,
      'city_id': 46,
      'city_name': 'Sorocaba',
      'display_name': 'Rafael Nunes',
      'agency_type': null,
      'requester_role': null,
      'party': 'PEX',
      'mandate_starts_on': '2025-01-01',
      'mandate_ends_on': '2028-12-31',
      'institutional_email': 'rafael@gmail.com',
      'proof_summary': 'Diploma emitido pelo TRE-SP.',
      'proof_links': 'https://tre-sp.jus.br/diploma, camara.sp.gov.br/vereadores',
      'requester_user_id': '20000000-0000-0000-0000-000000000003',
      'requester_name': 'Rafael Nunes',
      'requester_username': 'rafael.nunes',
      'requester_account_email': 'rafael@urbapp.test',
      'requester_since': '2026-04-01T10:00:00Z',
      'previous_requests': 2,
      'previous_rejections': 1,
      'existing_profile_status': null,
      'created_at': '2026-10-24T09:00:00Z',
      'reviewed_at': status == 'pending' ? null : '2026-10-25T11:00:00Z',
      'reviewer_name': status == 'pending' ? null : 'Administração UrbApp',
      'review_notes': status == 'rejected' ? 'Falta documento que comprove o mandato.' : null,
    };

Future<void> _pumpDetail(
  WidgetTester tester,
  InstitutionalVerificationRequest request,
  List<(bool, String)> calls,
) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    home: InstitutionalRequestDetailScreen(
      request: request,
      onReview: (approve, notes) async => calls.add((approve, notes)),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('Regras da verificação institucional', () {
    test('rejeição exige motivo com pelo menos 10 caracteres', () {
      expect(validateRejectionReason(''), isNotNull);
      expect(validateRejectionReason('   curto   '), isNotNull);
      expect(validateRejectionReason('Sem comprovação do vínculo.'), isNull);
      expect(minRejectionReasonLength, 10);
    });

    test('tipos e decisões seguem os códigos do backend', () {
      expect(institutionalRequestKindLabel('councilor'), 'Vereador');
      expect(institutionalRequestKindLabel('administration'), 'Gestão municipal');
      expect(institutionalRequestKindLabel('agency'), 'Órgão municipal');
      expect(institutionalRequestStatusLabel('approved'), 'Aprovada');
      expect(institutionalRequestStatusLabel('rejected'), 'Rejeitada');
      expect(institutionalRequestStatusLabel('pending'), 'Em análise');
    });

    test('a situação do perfil indica se a aprovação cria ou reivindica', () {
      expect(existingProfileLabel('agency', null), contains('Órgão novo'));
      expect(existingProfileLabel('agency', 'unclaimed'), contains('não foi reivindicado'));
      expect(existingProfileLabel('agency', 'participant'), contains('já reivindicado'));
      expect(existingProfileLabel('councilor', 'verified'), contains('verificado'));
      expect(existingProfileLabel('administration', 'unclaimed'), contains('Primeiro acesso'));
    });

    test('e-mail pessoal e rejeições anteriores viram alertas, não bloqueios', () {
      expect(institutionalReviewWarnings(institutionalEmail: 'ana@gmail.com', previousRejections: 0),
          ['O e-mail informado é de provedor pessoal, não institucional.']);
      expect(institutionalReviewWarnings(institutionalEmail: 'ana@sorocaba.sp.gov.br', previousRejections: 0), isEmpty);
      expect(institutionalReviewWarnings(institutionalEmail: 'ana@sorocaba.sp.gov.br', previousRejections: 2),
          ['Este solicitante já teve 2 pedidos rejeitados.']);
    });
  });

  group('Pedido institucional (modelo)', () {
    test('lê todos os campos da fila da administração', () {
      final request = InstitutionalVerificationRequest.fromJson(_row());
      expect(request.id, 7);
      expect(request.isCouncilor, isTrue);
      expect(request.isPending, isTrue);
      expect(request.party, 'PEX');
      expect(request.mandateStartsOn, DateTime.parse('2025-01-01'));
      expect(request.requesterUsername, 'rafael.nunes');
      expect(request.requesterAccountEmail, 'rafael@urbapp.test');
      expect(request.previousRequests, 2);
      expect(request.previousRejections, 1);
      expect(request.proofLinkList, ['https://tre-sp.jus.br/diploma', 'camara.sp.gov.br/vereadores']);
    });

    test('pedido decidido traz quem revisou e o motivo', () {
      final request = InstitutionalVerificationRequest.fromJson(_row(status: 'rejected'));
      expect(request.isPending, isFalse);
      expect(request.isApproved, isFalse);
      expect(request.reviewerName, 'Administração UrbApp');
      expect(request.reviewNotes, 'Falta documento que comprove o mandato.');
    });

    test('a notificação da decisão é reconhecida pelo tipo e pela decisão', () {
      AppNotification notification(String decision) => AppNotification.fromJson({
            'id': 1,
            'type': 'institutional_review',
            'title': 'Perfil institucional aprovado',
            'body': '...',
            'created_at': '2026-10-25T11:00:00Z',
            'payload': {'decision': decision, 'request_type': 'councilor', 'request_id': 7},
          });
      expect(notification('approved').isInstitutionalReview, isTrue);
      expect(notification('approved').isInstitutionalApproval, isTrue);
      expect(notification('rejected').isInstitutionalApproval, isFalse);
    });

    test('a decisão aparece na central de Alertas', () {
      expect(NotificationsService.visibleTypes, contains('institutional_review'));
    });
  });

  group('Detalhe do pedido (tela da administração)', () {
    testWidgets('mostra pedido, solicitante, comprovação e alertas', (tester) async {
      await _pumpDetail(tester, InstitutionalVerificationRequest.fromJson(_row()), []);
      expect(find.text('Rafael Nunes'), findsWidgets);
      expect(find.text('@rafael.nunes'), findsOneWidget);
      expect(find.text('rafael@urbapp.test'), findsOneWidget);
      expect(find.text('PEX'), findsOneWidget);
      expect(find.text('Diploma emitido pelo TRE-SP.'), findsOneWidget);
      expect(find.text('https://tre-sp.jus.br/diploma'), findsOneWidget);
      expect(find.text('O e-mail informado é de provedor pessoal, não institucional.'), findsOneWidget);
      expect(find.text('Este solicitante já teve 1 pedido rejeitado.'), findsOneWidget);
      expect(find.text('Aprovar'), findsOneWidget);
      expect(find.text('Rejeitar'), findsOneWidget);
    });

    testWidgets('rejeitar só é liberado com motivo e envia o motivo', (tester) async {
      final calls = <(bool, String)>[];
      await _pumpDetail(tester, InstitutionalVerificationRequest.fromJson(_row()), calls);

      await tester.tap(find.text('Rejeitar'));
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(InkWell, 'Rejeitar pedido');
      await tester.tap(find.text('Rejeitar pedido'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty, reason: 'sem motivo o botão não envia');

      await tester.enterText(find.byType(TextField), 'curto');
      await tester.pump();
      await tester.tap(find.text('Rejeitar pedido'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty, reason: 'motivo curto demais não envia');

      await tester.enterText(find.byType(TextField), '  Falta documento que comprove o mandato.  ');
      await tester.pump();
      await tester.tap(find.text('Rejeitar pedido'));
      await tester.pumpAndSettle();
      expect(calls, [(false, 'Falta documento que comprove o mandato.')]);
      expect(confirm, findsNothing);
    });

    testWidgets('aprovar pede confirmação antes de enviar', (tester) async {
      final calls = <(bool, String)>[];
      await _pumpDetail(tester, InstitutionalVerificationRequest.fromJson(_row()), calls);

      await tester.tap(find.text('Aprovar'));
      await tester.pumpAndSettle();
      expect(find.text('Aprovar pedido?'), findsOneWidget);
      expect(calls, isEmpty);

      await tester.tap(find.text('Aprovar').last);
      await tester.pumpAndSettle();
      expect(calls, [(true, '')]);
    });

    testWidgets('pedido do histórico mostra a decisão e não tem ações', (tester) async {
      await _pumpDetail(tester, InstitutionalVerificationRequest.fromJson(_row(status: 'rejected')), []);
      expect(find.textContaining('Rejeitada por Administração UrbApp'), findsOneWidget);
      expect(find.text('Falta documento que comprove o mandato.'), findsOneWidget);
      expect(find.text('Aprovar'), findsNothing);
      expect(find.text('Rejeitar'), findsNothing);
    });
  });
}
