import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:meu_app/app/routes.dart';
import 'package:meu_app/screens/ranking/ranking_screen.dart';
import 'package:meu_app/screens/transparency/administration_profile_screen.dart';
import 'package:meu_app/screens/transparency/transparency_screen.dart';
import 'package:meu_app/widgets/urb/urb_components.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Abre [open] a partir de uma tela de origem simples.
Future<void> _pumpOrigin(WidgetTester tester, Future<void> Function(BuildContext context) open) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(child: TextButton(onPressed: () => open(context), child: const Text('Origem'))),
      ),
    ),
  ));
  await tester.tap(find.text('Origem'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Volta pelo botão do cabeçalho, como o usuário.
Future<void> _goBack(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Voltar'));
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Armazenamento PKCE em memória (sem SharedPreferences nos testes).
class _MemoryStorage extends GotrueAsyncStorage {
  final _values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _values[key];

  @override
  Future<void> setItem({required String key, required String value}) async => _values[key] = value;

  @override
  Future<void> removeItem({required String key}) async => _values.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Supabase sem servidor: as telas mostram o estado de erro, mas a navegação
    // e os modos podem ser verificados.
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'chave-de-teste',
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStorage(),
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
    );
  });

  group('Rankings', () {
    testWidgets('a página principal mostra Cidades e Cidadãos juntos, sem abas', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RankingsScreen()));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Rankings'), findsOneWidget);
      expect(find.text('Cidades'), findsOneWidget);
      expect(find.textContaining('Cidadãos em'), findsOneWidget);
      expect(find.text('Ver ranking de cidades'), findsOneWidget);
      expect(find.text('Ver ranking de cidadãos'), findsOneWidget);
      expect(find.byType(UrbUnderlineTabs), findsNothing);
      // Cidades vem primeiro, com a mesma estrutura de Cidadãos.
      expect(
        tester.getTopLeft(find.text('Cidades')).dy,
        lessThan(tester.getTopLeft(find.textContaining('Cidadãos em')).dy),
      );
    });

    testWidgets('Ver ranking de cidades abre o comparativo e o voltar retorna', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RankingsScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Ver ranking de cidades'));
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(CityRankingScreen), findsOneWidget);
      await _goBack(tester);
      expect(find.byType(CityRankingScreen), findsNothing);
      expect(find.text('Ver ranking de cidades'), findsOneWidget);
    });

    testWidgets('Ver ranking de cidadãos abre a lista completa', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RankingsScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Ver ranking de cidadãos'));
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(CitizenRankingScreen), findsOneWidget);
    });

    testWidgets('no ranking de cidadãos, Geral vem primeiro e abre selecionado', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(home: CitizenRankingScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getCenter(find.text('Geral')).dx, lessThan(tester.getCenter(find.text('Este mês')).dx));
      final general = tester.widget<UrbChip>(find.widgetWithText(UrbChip, 'Geral'));
      final month = tester.widget<UrbChip>(find.widgetWithText(UrbChip, 'Este mês'));
      expect(general.selected, isTrue);
      expect(month.selected, isFalse);
      semantics.dispose();
    });

    testWidgets('Transparência abre a página principal de Rankings', (tester) async {
      await _pumpOrigin(tester, (context) => openRankings(context));
      expect(find.byType(RankingsScreen), findsOneWidget);
    });

    testWidgets('a posição no Perfil abre o ranking completo de cidadãos', (tester) async {
      await _pumpOrigin(tester, (context) => openCitizenRanking(context));
      expect(find.byType(CitizenRankingScreen), findsOneWidget);
    });
  });

  group('Transparência como visão da cidade', () {
    testWidgets('na aba principal acompanha a cidade selecionada, sem voltar', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TransparencyScreen())));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(UrbScreenHeader), findsOneWidget);
      expect(find.byType(UrbSubscreenHeader), findsNothing);
    });

    testWidgets('outra cidade abre a mesma Transparência, contextualizada e com voltar', (tester) async {
      await _pumpOrigin(tester, (context) => openCityTransparency(context, 5));
      final screen = tester.widget<TransparencyScreen>(find.byType(TransparencyScreen));
      expect(screen.cityId, 5);
      expect(find.byType(UrbSubscreenHeader), findsOneWidget);
      await _goBack(tester);
      expect(find.byType(TransparencyScreen), findsNothing);
      expect(find.text('Origem'), findsOneWidget);
    });

    testWidgets('a Gestão Municipal continua com tela própria', (tester) async {
      await _pumpOrigin(tester, (context) => openAdministration(context, administrationId: 7));
      final screen = tester.widget<AdministrationProfileScreen>(find.byType(AdministrationProfileScreen));
      expect(screen.administrationId, 7);
      await _goBack(tester);
      expect(find.text('Origem'), findsOneWidget);
    });
  });

  group('Contrato de navegação', () {
    String source(String path) => File(path).readAsStringSync();

    test('a aba Transparência do bottom nav usa a cidade atual', () {
      expect(source('lib/screens/shell/app_shell.dart'), contains('UrbTab.transparency => const TransparencyScreen()'));
    });

    test('não existe tela ou rota duplicada de Perfil da Cidade', () {
      final dartFiles = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
      for (final file in dartFiles) {
        expect(file.readAsStringSync(), isNot(contains('CityProfileScreen')), reason: file.path);
      }
      expect(File('lib/screens/transparency/city_profile_screen.dart').existsSync(), isFalse);
    });

    test('Transparência tem uma única entrada para Rankings e abre a Gestão', () {
      final transparency = source('lib/screens/transparency/transparency_screen.dart');
      expect('openRankings(context)'.allMatches(transparency).length, greaterThanOrEqualTo(1));
      expect(transparency, isNot(contains('openCityRanking(')));
      expect(transparency, isNot(contains('openCitizenRanking(')));
      expect(transparency, contains('openAdministration(context, administrationId: administration.id)'));
    });

    test('Perfil abre o ranking completo de cidadãos', () {
      expect(source('lib/screens/profile/profile_screen.dart'), contains('openCitizenRanking(context)'));
    });

    test('Rankings não usa mais abas de modo', () {
      final ranking = source('lib/screens/ranking/ranking_screen.dart');
      expect(ranking, isNot(contains('RankingMode')));
      expect(ranking, isNot(contains('UrbUnderlineTabs')));
    });

    test('cidade no comparativo abre a Transparência daquela cidade', () {
      expect(source('lib/screens/ranking/ranking_screen.dart'), contains('openCityTransparency(context, row.cityId)'));
    });
  });
}
