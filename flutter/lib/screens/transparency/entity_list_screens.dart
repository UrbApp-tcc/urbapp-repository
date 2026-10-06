import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../domain/labels.dart';
import '../../services/location_service.dart';
import '../../services/transparency_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import 'transparency_widgets.dart';

const _agencyDots = [UrbColors.blue, UrbColors.orange, UrbColors.teal, UrbColors.gold, UrbColors.violet];

class AgencyListRow extends StatelessWidget {
  const AgencyListRow({super.key, required this.agency, required this.index, this.last = false});

  final AgencyProfile agency;
  final int index;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openAgency(context, agency.id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: UrbColors.line))),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: _agencyDots[index % _agencyDots.length], shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(agency.name, style: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w600)),
                  if (!agency.status.isVerified)
                    Text('Perfil não reivindicado', style: UrbText.caption.copyWith(fontSize: 10.5)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${formatCount(agency.assigned)} ${agency.assigned == 1 ? 'ocorrência' : 'ocorrências'}',
              style: UrbText.meta,
            ),
            const SizedBox(width: 4),
            const UrbIcon(UrbIcons.chevron, size: 15, color: UrbColors.muted),
          ],
        ),
      ),
    );
  }
}

class _SearchableList<T> extends StatefulWidget {
  const _SearchableList({
    required this.title,
    required this.eyebrow,
    required this.intro,
    required this.items,
    required this.nameOf,
    required this.rowBuilder,
  });

  final String title;
  final String eyebrow;
  final String intro;
  final List<T> items;
  final String Function(T) nameOf;
  final Widget Function(T item, int index, bool last) rowBuilder;

  @override
  State<_SearchableList<T>> createState() => _SearchableListState<T>();
}

class _SearchableListState<T> extends State<_SearchableList<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final normalized = LocationService.normalize(_query);
    final filtered = widget.items
        .where((item) => normalized.isEmpty || LocationService.normalize(widget.nameOf(item)).contains(normalized))
        .toList();
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: UrbSubscreenHeader(title: widget.title),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          UrbEyebrow(widget.eyebrow),
          const SizedBox(height: 8),
          Text(widget.intro, style: UrbText.bodySmall),
          const SizedBox(height: 16),
          UrbTextField(
            hint: 'Buscar por nome',
            prefix: const Padding(padding: EdgeInsets.all(14), child: UrbIcon(UrbIcons.search, size: 17, color: UrbColors.muted)),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            const UrbEmptyState(compact: true, title: 'Nada encontrado', message: 'Confira a grafia do nome.')
          else
            for (var index = 0; index < filtered.length; index++)
              widget.rowBuilder(filtered[index], index, index == filtered.length - 1),
        ],
      ),
    );
  }
}

/// Lista de órgãos em ordem alfabética (sem classificação).
class AgenciesListScreen extends StatelessWidget {
  const AgenciesListScreen({super.key, required this.agencies});

  final List<AgencyProfile> agencies;

  @override
  Widget build(BuildContext context) {
    return _SearchableList<AgencyProfile>(
      title: 'Órgãos públicos',
      eyebrow: 'Ordem alfabética',
      intro: 'Perfis criados para organizar as ocorrências. Existem mesmo antes de o órgão aderir ao UrbApp.',
      items: agencies,
      nameOf: (agency) => agency.name,
      rowBuilder: (agency, index, last) => AgencyListRow(agency: agency, index: index, last: last),
    );
  }
}

/// Lista de vereadores em ordem alfabética (sem ranking político, spec §22).
class CouncilorsListScreen extends StatelessWidget {
  const CouncilorsListScreen({super.key, required this.councilors});

  final List<CouncilorProfile> councilors;

  @override
  Widget build(BuildContext context) {
    return _SearchableList<CouncilorProfile>(
      title: 'Vereadores',
      eyebrow: 'Ordem alfabética',
      intro: 'Perfis verificados mostram atividade factual na plataforma: demandas acompanhadas e ações registradas.',
      items: councilors,
      nameOf: (councilor) => councilor.publicName,
      rowBuilder: (councilor, index, last) => InkWell(
        onTap: () => openCouncilor(context, councilor.id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: UrbColors.line))),
          child: Row(
            children: [
              PersonAvatar(name: councilor.publicName, seed: councilor.id, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(councilor.publicName, style: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      [if (councilor.party != null) councilor.party!, councilor.mandateLabel].where((part) => part.isNotEmpty).join(' · '),
                      style: UrbText.caption,
                    ),
                  ],
                ),
              ),
              Text('${councilor.followedOpen} em acompanhamento', style: UrbText.caption),
              const SizedBox(width: 4),
              const UrbIcon(UrbIcons.chevron, size: 15, color: UrbColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
