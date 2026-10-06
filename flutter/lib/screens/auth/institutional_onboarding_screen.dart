import 'package:flutter/material.dart';

import '../../app/institutional_intent.dart';
import '../../app/routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import 'register_screen.dart';

/// Entrada institucional a partir do login: explica a verificação e leva ao
/// cadastro já marcado com o papel escolhido. A conta continua sendo uma só;
/// as funções institucionais só são liberadas após análise (spec §3.5).
///
/// Retorna o papel escolhido quando a pessoa já tem conta e vai entrar.
class InstitutionalOnboardingScreen extends StatefulWidget {
  const InstitutionalOnboardingScreen({super.key});

  @override
  State<InstitutionalOnboardingScreen> createState() => _InstitutionalOnboardingScreenState();
}

class _InstitutionalOnboardingScreenState extends State<InstitutionalOnboardingScreen> {
  InstitutionalKind? _kind;

  Future<void> _createAccount() async {
    final kind = _kind;
    if (kind == null) {
      showUrbToast(context, 'Escolha como você vai atuar no UrbApp.');
      return;
    }
    final created = await Navigator.of(context).push<bool>(urbRoute(RegisterScreen(institutionalKind: kind)));
    if (created == true && mounted) Navigator.of(context).pop();
  }

  void _signIn() {
    final kind = _kind;
    if (kind == null) {
      showUrbToast(context, 'Escolha como você vai atuar no UrbApp.');
      return;
    }
    InstitutionalIntent.pending = kind;
    Navigator.of(context).pop(kind);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Acesso institucional'),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
          children: [
            const UrbEyebrow('Para instituições'),
            const SizedBox(height: 8),
            Text('Atue pela sua instituição no UrbApp', style: UrbText.h1),
            const SizedBox(height: 8),
            Text(
              'Vereadores, órgãos municipais e a gestão municipal usam o mesmo aplicativo dos cidadãos, '
              'com funções adicionais nas ocorrências da cidade.',
              style: UrbText.body,
            ),
            const SizedBox(height: 22),
            Text('Como você vai atuar?', style: UrbText.label.copyWith(color: UrbColors.navy)),
            const SizedBox(height: 10),
            for (final kind in InstitutionalKind.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _KindCard(kind: kind, selected: kind == _kind, onTap: () => setState(() => _kind = kind)),
              ),
            const SizedBox(height: 12),
            Text('Como funciona', style: UrbText.label.copyWith(color: UrbColors.navy)),
            const SizedBox(height: 10),
            const _Step(number: 1, title: 'Crie sua conta', message: 'De preferência com o seu e-mail institucional.'),
            const _Step(
              number: 2,
              title: 'Envie a comprovação',
              message: 'Logo após entrar, você informa a cidade, o cargo e como comprovar o vínculo.',
            ),
            const _Step(
              number: 3,
              title: 'Verificação pelo UrbApp',
              message: 'A equipe confere o vínculo antes de liberar as funções institucionais.',
              last: true,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: UrbColors.blueSoft, borderRadius: BorderRadius.circular(12)),
              child: Text(
                'Nenhum papel institucional é concedido sem verificação. Enquanto a análise acontece, '
                'você pode usar o UrbApp normalmente.',
                style: UrbText.caption.copyWith(color: UrbColors.navy),
              ),
            ),
            const SizedBox(height: 22),
            UrbPrimaryButton(label: 'Criar conta institucional', onPressed: _createAccount),
            const SizedBox(height: 12),
            Center(child: UrbTextButton('Já tenho conta no UrbApp', onPressed: _signIn)),
          ],
        ),
      ),
    );
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({required this.kind, required this.selected, required this.onTap});

  final InstitutionalKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: '${kind.choice}. ${kind.description}',
      excludeSemantics: true,
      child: Material(
        color: selected ? UrbColors.blueSoft : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(color: selected ? UrbColors.blue : UrbColors.line, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(kind.choice, style: UrbText.title.copyWith(fontSize: 15)),
                      const SizedBox(height: 3),
                      Text(kind.description, style: UrbText.caption.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? UrbColors.blue : Colors.white,
                    border: Border.all(color: selected ? UrbColors.blue : UrbColors.line, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: selected ? const UrbIcon(UrbIcons.check, size: 13, color: Colors.white) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.message, this.last = false});

  final int number;
  final String title;
  final String message;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: UrbColors.lime, borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: Text('$number', style: UrbText.label.copyWith(color: UrbColors.navy, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w800)),
                Text(message, style: UrbText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
