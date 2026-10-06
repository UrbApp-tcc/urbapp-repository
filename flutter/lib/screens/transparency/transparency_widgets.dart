import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../domain/labels.dart';
import '../../services/transparency_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';

/// Seção editorial com borda inferior (padrão das telas de Transparência).
class TransSection extends StatelessWidget {
  const TransSection({super.key, required this.child, this.white = false, this.last = false});

  final Widget child;
  final bool white;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
      decoration: BoxDecoration(
        color: white ? Colors.white : null,
        border: last ? null : const Border(bottom: BorderSide(color: UrbColors.line)),
      ),
      child: child,
    );
  }
}

class TransEyebrow extends StatelessWidget {
  const TransEyebrow(this.text, {super.key, this.trailing, this.subtitle});

  final String text;
  final Widget? trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text.toUpperCase(), style: UrbText.eyebrow.copyWith(color: UrbColors.muted, letterSpacing: 1.4)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: UrbText.caption.copyWith(fontWeight: FontWeight.w500)),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Cabeçalho de identidade dos perfis públicos (vereador, órgão, gestão).
class PublicIdentity extends StatelessWidget {
  const PublicIdentity({
    super.key,
    required this.mark,
    required this.title,
    this.overline,
    this.lines = const [],
    this.chips = const [],
    required this.verificationLabel,
    required this.verified,
  });

  final Widget mark;
  final String title;
  final String? overline;
  final List<String> lines;
  final List<String> chips;
  final String verificationLabel;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: UrbColors.line))),
      child: Column(
        children: [
          mark,
          const SizedBox(height: 14),
          if (overline != null) ...[
            Text(overline!, style: UrbText.caption.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2)),
            const SizedBox(height: 5),
          ],
          Text(title, textAlign: TextAlign.center, style: UrbText.h2.copyWith(color: UrbColors.navy)),
          for (final line in lines) ...[
            const SizedBox(height: 4),
            Text(line, textAlign: TextAlign.center, style: UrbText.meta.copyWith(fontWeight: FontWeight.w500)),
          ],
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final chip in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: UrbColors.blueSoft, borderRadius: BorderRadius.circular(20)),
                    child: Text(chip, style: UrbText.caption.copyWith(color: UrbColors.blue, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          UrbVerificationPill(label: verificationLabel, verified: verified, large: true),
        ],
      ),
    );
  }
}

/// Destaque numérico com rótulo ("72% das ocorrências com resposta oficial").
class RateNote extends StatelessWidget {
  const RateNote({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: UrbColors.line),
      ),
      child: Row(
        children: [
          Text(value, style: UrbText.h3.copyWith(fontSize: 19, letterSpacing: -0.8)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: UrbText.caption.copyWith(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

/// Nota de origem dos dados: calculado pelo UrbApp × informação oficial.
class DataSourceNote extends StatelessWidget {
  const DataSourceNote(this.text, {super.key, this.official = false});

  final String text;
  final bool official;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          UrbIcon(official ? UrbIcons.megaphone : UrbIcons.list, size: 13, color: UrbColors.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: UrbText.caption.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar de pessoa com gradiente (vereadores).
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, required this.seed, this.size = 54, this.highlighted = false});

  final String name;
  final int seed;
  final double size;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: highlighted
          ? BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                const BoxShadow(color: Colors.white, spreadRadius: 2.5),
                BoxShadow(color: UrbColors.blue, spreadRadius: 4.5),
              ],
            )
          : null,
      child: UrbAvatar(name: name, size: size, rounded: false, gradientSeed: seed),
    );
  }
}

class PublicProfileScaffold extends StatelessWidget {
  const PublicProfileScaffold({super.key, required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 14, 20, 14),
            child: Row(
              children: [
                UrbSquareButton(
                  icon: UrbIcons.chevronLeft,
                  tooltip: 'Voltar',
                  size: 36,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const Spacer(),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Segmento da barra de proporção (estado das ocorrências).
class ProportionSegment {
  const ProportionSegment(this.value, this.label, this.color);

  final int value;
  final String label;
  final Color color;
}

/// Barra única de proporção: uma leitura só, em vez de uma grade de métricas.
class ProportionBar extends StatelessWidget {
  const ProportionBar({super.key, required this.segments, required this.total});

  final List<ProportionSegment> segments;
  final int total;

  @override
  Widget build(BuildContext context) {
    final visible = segments.where((segment) => segment.value > 0).toList();
    return Semantics(
      label: visible.map((segment) => '${segment.value} ${segment.label}').join(', '),
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 8,
          child: total == 0 || visible.isEmpty
              ? Container(color: UrbColors.line)
              : Row(
                  children: [
                    for (var index = 0; index < visible.length; index++) ...[
                      if (index > 0) const SizedBox(width: 2),
                      Expanded(flex: visible[index].value, child: Container(color: visible[index].color)),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class ProportionLegend extends StatelessWidget {
  const ProportionLegend({super.key, required this.segment});

  final ProportionSegment segment;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: segment.color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${formatCount(segment.value)} ',
                style: UrbText.caption.copyWith(color: UrbColors.navy, fontWeight: FontWeight.w800),
              ),
              TextSpan(text: segment.label),
            ],
          ),
          style: UrbText.caption,
        ),
      ],
    );
  }
}

/// Faixa horizontal de vereadores: pessoas, sem notas nem classificação.
class CouncilorStrip extends StatelessWidget {
  const CouncilorStrip({super.key, required this.councilors});

  final List<CouncilorProfile> councilors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: councilors.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final councilor = councilors[index];
          return Semantics(
            button: true,
            label: '${councilor.publicName}${councilor.party == null ? '' : ', ${councilor.party}'}',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => openCouncilor(context, councilor.id),
              child: SizedBox(
                width: 64,
                child: Column(
                  children: [
                    PersonAvatar(name: councilor.publicName, seed: councilor.id),
                    const SizedBox(height: 7),
                    Text(
                      councilor.publicName.split(' ').first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.caption.copyWith(color: UrbColors.navy, fontWeight: FontWeight.w700),
                    ),
                    Text(councilor.party ?? '', style: UrbText.caption.copyWith(fontSize: 10, letterSpacing: 0.5)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
