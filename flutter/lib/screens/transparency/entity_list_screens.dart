import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../services/transparency_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import 'transparency_kit.dart';

// Listas da Transparência: órgãos (em grade de blocos) e vereadores (cartões
// com fatos). Ambas em ordem alfabética, nunca por desempenho (spec §44.6).

/// Grade 2×N de órgãos: monograma, selo de adesão, nome e contagem.
class AgencyGrid extends StatelessWidget {
  const AgencyGrid({super.key, required this.agencies});

  final List<AgencyProfile> agencies;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < agencies.length; index += 2) ...[
          if (index > 0) const SizedBox(height: 10),
          TilePair(
            left: _AgencyTile(agency: agencies[index]),
            right: index + 1 < agencies.length ? _AgencyTile(agency: agencies[index + 1]) : const SizedBox.shrink(),
          ),
        ],
      ],
    );
  }
}

class _AgencyTile extends StatelessWidget {
  const _AgencyTile({required this.agency});

  final AgencyProfile agency;

  @override
  Widget build(BuildContext context) {
    final status = agency.status;
    final count = plural(agency.assigned, 'ocorrência', 'ocorrências');
    return BentoTile(
      height: 150,
      onTap: () => openAgency(context, agency.id),
      semanticsLabel: '${agency.name}. ${status.label}. $count',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Monogram(name: agency.name, size: 38),
              const Spacer(),
              if (status.isVerified)
                institutionalPill(
                  status.label,
                  claimed: true,
                  participant: status == InstitutionalProfileStatus.participant,
                )!,
            ],
          ),
          const Spacer(),
          Text(
            agency.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: UrbText.label.copyWith(fontSize: 14, fontWeight: FontWeight.w800, color: UrbColors.ink, height: 1.25),
          ),
          const SizedBox(height: 3),
          Text(count, style: tileSubtitleStyle()),
        ],
      ),
    );
  }
}

/// Órgãos de uma cidade sem Gestão cadastrada.
class AgenciesListScreen extends StatelessWidget {
  const AgenciesListScreen({super.key, required this.agencies});

  final List<AgencyProfile> agencies;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Órgãos'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
            child: Text(
              '${plural(agencies.length, 'órgão responde', 'órgãos respondem')} pelas categorias de problema',
              style: UrbText.label.copyWith(fontWeight: FontWeight.w700, color: UrbColors.muted),
            ),
          ),
          AgencyGrid(agencies: agencies),
        ],
      ),
    );
  }
}

/// Vereadores verificados da cidade: busca e cartões só com fatos.
class CouncilorsListScreen extends StatefulWidget {
  const CouncilorsListScreen({super.key, required this.councilors, required this.cityName});

  final List<CouncilorProfile> councilors;
  final String cityName;

  @override
  State<CouncilorsListScreen> createState() => _CouncilorsListScreenState();
}

class _CouncilorsListScreenState extends State<CouncilorsListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final term = _query.trim().toLowerCase();
    final shown = term.isEmpty
        ? widget.councilors
        : widget.councilors
            .where((item) => '${item.publicName} ${item.party ?? ''}'.toLowerCase().contains(term))
            .toList();
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Vereadores'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          Text(
            'Câmara de\n${widget.cityName}',
            style: bigNumberStyle(30).copyWith(letterSpacing: -1.5, height: 1.12),
          ),
          const SizedBox(height: 8),
          Text(
            'Perfis verificados no UrbApp. Mostramos só o que cada perfil registrou, sem notas nem classificação.',
            style: UrbText.label.copyWith(fontWeight: FontWeight.w600, color: UrbColors.muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          if (widget.councilors.length > 1) ...[
            _SearchField(onChanged: (value) => setState(() => _query = value)),
            const SizedBox(height: 10),
          ],
          if (widget.councilors.isEmpty)
            const SoftEmpty(
              title: 'Nenhum vereador verificado ainda',
              message: 'Quando um vereador da cidade verificar o perfil, a atividade dele aparece aqui. '
                  'Acompanhar uma demanda é opcional e não substitui a validação dos vizinhos.',
            )
          else ...[
            for (final councilor in shown) ...[
              _CouncilorCard(councilor: councilor),
              const SizedBox(height: 10),
            ],
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('Nenhum perfil encontrado.', textAlign: TextAlign.center, style: tileSubtitleStyle()),
              ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: UrbColors.line),
              ),
              child: Text(
                'Outros vereadores aparecem aqui quando verificarem o perfil. Acompanhar uma demanda é opcional '
                'e não substitui a validação dos vizinhos.',
                style: UrbText.label.copyWith(fontWeight: FontWeight.w600, color: UrbColors.muted, height: 1.4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      style: UrbText.body.copyWith(color: UrbColors.ink),
      decoration: InputDecoration(
        hintText: 'Buscar por nome ou partido',
        hintStyle: UrbText.body.copyWith(color: UrbColors.muted, fontWeight: FontWeight.w600),
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: 14, right: 10),
          child: UrbIcon(UrbIcons.search, size: 18, color: UrbColors.muted),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: UrbColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: UrbColors.blue),
        ),
      ),
    );
  }
}

class _CouncilorCard extends StatelessWidget {
  const _CouncilorCard({required this.councilor});

  final CouncilorProfile councilor;

  @override
  Widget build(BuildContext context) {
    final meta = [?councilor.party, if (councilor.mandateLabel.isNotEmpty) councilor.mandateLabel].join(' · ');
    return BentoTile(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      onTap: () => openCouncilor(context, councilor.id),
      semanticsLabel: '${councilor.publicName}. $meta. ${plural(councilor.followed, 'demanda acompanhada', 'demandas acompanhadas')}, '
          '${plural(councilor.registeredActions, 'ação registrada', 'ações registradas')}',
      child: Row(
        children: [
          InitialsAvatar(name: councilor.publicName, size: 52, background: UrbColors.blue),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        councilor.publicName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: UrbText.title.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3, color: UrbColors.ink),
                      ),
                    ),
                    if (councilor.status.isVerified) ...[const SizedBox(width: 6), const OfficialMark(size: 16)],
                  ],
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(meta, style: tileSubtitleStyle()),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Fact(value: councilor.followed, label: pluralWord(councilor.followed, 'acompanhada', 'acompanhadas')),
                    const SizedBox(width: 14),
                    _Fact(value: councilor.registeredActions, label: pluralWord(councilor.registeredActions, 'ação', 'ações')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const UrbIcon(UrbIcons.chevron, size: 16, color: UrbColors.muted),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: formatCount(value),
        style: UrbText.title.copyWith(fontSize: 15, fontWeight: FontWeight.w800, color: UrbColors.ink),
        children: [TextSpan(text: ' $label', style: tileSubtitleStyle())],
      ),
    );
  }
}
