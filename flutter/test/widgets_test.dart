import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:meu_app/domain/models.dart';
import 'package:meu_app/domain/occurrence_status.dart';
import 'package:meu_app/widgets/urb/occurrence_widgets.dart';
import 'package:meu_app/widgets/urb/urb_bottom_nav.dart';
import 'package:meu_app/widgets/urb/urb_components.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Occurrence _occurrence({OccurrenceStatus status = OccurrenceStatus.open, bool supported = false}) => Occurrence(
      id: 1,
      title: 'Poste apagado na praça',
      status: status,
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
      latitude: -23.5,
      longitude: -47.4,
      neighborhood: 'Vila Carvalho',
      cityId: 1,
      cityName: 'Sorocaba',
      categoryId: 1,
      categoryName: 'Iluminação pública',
      administrationId: 1,
      reportsCount: 3,
      supportsCount: 51,
      commentsCount: 8,
      supportedByMe: supported,
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a navegação principal segue Início · Buscar · Relatar · Transparência · Perfil', (tester) async {
    await tester.pumpWidget(_wrap(Align(
      alignment: Alignment.bottomCenter,
      child: UrbBottomNav(current: UrbTab.home, onSelect: (_) {}, onCreate: () {}),
    )));
    final labels = ['Início', 'Buscar', 'Relatar', 'Transparência', 'Perfil'];
    final positions = [for (final label in labels) tester.getCenter(find.text(label)).dx];
    expect(positions, orderedEquals([...positions]..sort()));
    expect(find.text('Alertas'), findsNothing);
  });

  testWidgets('o botão Relatar aciona o fluxo de criação', (tester) async {
    var created = 0;
    UrbTab? selected;
    await tester.pumpWidget(_wrap(Align(
      alignment: Alignment.bottomCenter,
      child: UrbBottomNav(current: UrbTab.home, onSelect: (tab) => selected = tab, onCreate: () => created++),
    )));
    await tester.tap(find.text('Relatar'));
    await tester.tap(find.text('Transparência'));
    expect(created, 1);
    expect(selected, UrbTab.transparency);
  });

  testWidgets('botão primário fica desabilitado sem ação', (tester) async {
    await tester.pumpWidget(_wrap(const UrbPrimaryButton(label: 'Continuar', onPressed: null)));
    expect(
      tester.getSemantics(find.bySemanticsLabel('Continuar')),
      matchesSemantics(label: 'Continuar', isButton: true, hasEnabledState: true, isEnabled: false),
    );
  });

  testWidgets('linha de ocorrência mostra categoria, status, relatos e apoios', (tester) async {
    var opened = false;
    await tester.pumpWidget(_wrap(OccurrenceRow(occurrence: _occurrence(), onOpen: () => opened = true)));
    // A categoria acompanha o local; a situação vira selo e as métricas ficam numéricas.
    expect(find.textContaining('Iluminação pública'), findsOneWidget);
    expect(find.text('Aberto'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('51'), findsOneWidget);
    await tester.tap(find.text('Poste apagado na praça'));
    expect(opened, isTrue);
  });

  test('só o status Resolvido tem cor própria; os demais usam o selo neutro', () {
    final neutral = OccurrenceStatus.open.background;
    for (final status in OccurrenceStatus.values) {
      if (status == OccurrenceStatus.resolved) {
        expect(status.background, isNot(neutral), reason: status.label);
        expect(status.foreground, isNot(OccurrenceStatus.open.foreground));
      } else {
        expect(status.background, neutral, reason: status.label);
        expect(status.foreground, OccurrenceStatus.open.foreground, reason: status.label);
      }
    }
  });

  testWidgets('status Resolvido e Encerrado usam rótulos distintos', (tester) async {
    await tester.pumpWidget(_wrap(const Column(children: [
      StatusPill(OccurrenceStatus.resolved),
      StatusPill(OccurrenceStatus.closed),
    ])));
    expect(find.text('Resolvido'), findsOneWidget);
    expect(find.text('Encerrado'), findsOneWidget);
  });

  testWidgets('selo institucional distingue verificado de não reivindicado', (tester) async {
    await tester.pumpWidget(_wrap(Column(children: [
      UrbVerificationPill(label: InstitutionalProfileStatus.verified.label),
      UrbVerificationPill(label: InstitutionalProfileStatus.unclaimed.label, verified: false),
    ])));
    expect(find.text('Verificado'), findsOneWidget);
    expect(find.text('Não reivindicado'), findsOneWidget);
  });

  testWidgets('sino exibe contagem de alertas não lidos', (tester) async {
    await tester.pumpWidget(_wrap(UrbBellButton(unreadCount: 3, onPressed: () {})));
    expect(find.text('3'), findsOneWidget);
    expect(find.bySemanticsLabel('Alertas, 3 não lidos'), findsOneWidget);
  });
}
