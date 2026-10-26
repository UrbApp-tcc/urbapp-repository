import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/labels.dart';
import '../../theme/app_theme.dart';
import '../../widgets/urb/urb_icon.dart';

// Kit visual da Transparência em blocos: superfícies de 22px com um glifo
// sólido, um número grande de tracking apertado, um título forte e uma linha
// de apoio. Cada tela usa no máximo um momento de cor (navy, azul ou lime).

/// Raio dos blocos da Transparência.
const double kTileRadius = 22;

/// Cinza claro para zeros e partes "de N" que não devem competir com o número.
const Color kFaint = Color(0xFFB4BDC9);

/// Fundo neutro das notas e do controle segmentado.
const Color kSoft = Color(0xFFF1F3EE);

/// Texto de apoio sobre o lime.
const Color kOnLimeMuted = Color(0xFF3E4C2A);

enum TileTone { white, navy, blue, lime, soft }

/// Cores de texto que acompanham cada tom de bloco.
class TileInk {
  const TileInk(this.strong, this.muted);

  final Color strong;
  final Color muted;

  static TileInk of(TileTone tone) => switch (tone) {
        TileTone.navy => const TileInk(Colors.white, Color(0xFFAEB9CF)),
        TileTone.blue => const TileInk(Colors.white, Color(0xFFD3D8FF)),
        TileTone.lime => const TileInk(UrbColors.ink, kOnLimeMuted),
        _ => const TileInk(UrbColors.ink, UrbColors.muted),
      };
}

Color tileColor(TileTone tone) => switch (tone) {
      TileTone.white => Colors.white,
      TileTone.navy => UrbColors.navy,
      TileTone.blue => UrbColors.blue,
      TileTone.lime => UrbColors.lime,
      TileTone.soft => kSoft,
    };

/// Superfície base: tom, raio de 22px, borda fina só no branco.
class BentoTile extends StatelessWidget {
  const BentoTile({
    super.key,
    required this.child,
    this.tone = TileTone.white,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.semanticsLabel,
  });

  final Widget child;
  final TileTone tone;
  final double? height;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(kTileRadius),
      side: tone == TileTone.white ? const BorderSide(color: UrbColors.line) : BorderSide.none,
    );
    Widget content = Padding(padding: padding, child: child);
    if (height != null) content = SizedBox(height: height, child: content);
    final tile = Material(
      color: tileColor(tone),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
    if (semanticsLabel == null) return tile;
    return Semantics(
      button: onTap != null,
      label: semanticsLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: tile,
    );
  }
}

/// Número grande, título e apoio — a base tipográfica de todo bloco.
class TileStat extends StatelessWidget {
  const TileStat({
    super.key,
    this.value,
    this.valueSuffix,
    required this.title,
    this.subtitle,
    this.tone = TileTone.white,
    this.valueSize = 40,
    this.faintValue = false,
    this.titleSize = 13,
  });

  final String? value;

  /// Parte esmaecida do número ("de 7").
  final String? valueSuffix;
  final String title;
  final String? subtitle;
  final TileTone tone;
  final double valueSize;
  final bool faintValue;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final ink = TileInk.of(tone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (value != null)
          Text.rich(
            TextSpan(
              text: value,
              children: [
                if (valueSuffix != null)
                  TextSpan(text: valueSuffix, style: const TextStyle(color: kFaint)),
              ],
            ),
            maxLines: 1,
            style: bigNumberStyle(valueSize, color: faintValue ? kFaint : ink.strong),
          ),
        if (value != null) const SizedBox(height: 2),
        Text(
          title,
          style: UrbText.label.copyWith(
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            color: ink.strong,
            height: 1.25,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: tileSubtitleStyle(ink.muted)),
        ],
      ],
    );
  }
}

TextStyle bigNumberStyle(double size, {Color color = UrbColors.ink}) => UrbText.display.copyWith(
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.05 * size,
      height: 1.05,
      color: color,
    );

TextStyle tileSubtitleStyle([Color color = UrbColors.muted]) =>
    UrbText.meta.copyWith(fontSize: 12, fontWeight: FontWeight.w600, height: 1.33, color: color);

/// Bloco alto de grade: glifo no topo e o número com título embaixo.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.glyph,
    required this.stat,
    this.tone = TileTone.white,
    this.height = 200,
    this.onTap,
    this.semanticsLabel,
  });

  final Widget glyph;
  final TileStat stat;
  final TileTone tone;
  final double height;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return BentoTile(
      tone: tone,
      height: height,
      onTap: onTap,
      semanticsLabel: semanticsLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [glyph, stat],
      ),
    );
  }
}

/// Dois blocos lado a lado com a mesma altura.
class TilePair extends StatelessWidget {
  const TilePair({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    );
  }
}

/// Bloco largo e baixo: número à esquerda, título e apoio à direita.
class WideStat extends StatelessWidget {
  const WideStat({
    super.key,
    required this.value,
    required this.title,
    this.subtitle,
    this.faintValue = false,
    this.valueSize = 30,
    this.onTap,
  });

  final String value;
  final String title;
  final String? subtitle;
  final bool faintValue;
  final double valueSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return BentoTile(
      onTap: onTap,
      semanticsLabel: [value, title, ?subtitle].join(', '),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          Text(value, style: bigNumberStyle(valueSize, color: faintValue ? kFaint : UrbColors.ink)),
          const SizedBox(width: 14),
          Expanded(child: TileStat(title: title, subtitle: subtitle)),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            const UrbIcon(UrbIcons.chevron, size: 16, color: UrbColors.muted),
          ],
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Proveniência: o que o UrbApp calcula × o que a instituição publica (spec §12)
// -----------------------------------------------------------------------------

class Provenance extends StatelessWidget {
  const Provenance.calculated(this.text, {super.key}) : official = false;
  const Provenance.official(this.text, {super.key}) : official = true;

  final String text;
  final bool official;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 2),
      child: Row(
        children: [
          official ? const OfficialMark(size: 14) : const CalculatedMark(),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: UrbText.meta.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: UrbColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quadradinho azul com "U": calculado pelo UrbApp.
class CalculatedMark extends StatelessWidget {
  const CalculatedMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: UrbColors.blue, borderRadius: BorderRadius.circular(5)),
      child: Text('U', style: UrbText.caption.copyWith(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
    );
  }
}

/// Círculo navy com check lime: publicado oficialmente.
class OfficialMark extends StatelessWidget {
  const OfficialMark({super.key, this.size = 14});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: UrbColors.navy, shape: BoxShape.circle),
      child: UrbIcon(UrbIcons.check, size: size * 0.64, color: UrbColors.lime, strokeWidth: 3.6),
    );
  }
}

// -----------------------------------------------------------------------------
// Identidade: bloco herói, selos, monogramas e iniciais
// -----------------------------------------------------------------------------

/// Bloco de identidade no topo dos perfis (Gestão, órgão, vereador).
class IdentityHero extends StatelessWidget {
  const IdentityHero({
    super.key,
    required this.tone,
    required this.leading,
    this.badge,
    required this.name,
    this.line2,
    this.line3,
  });

  final TileTone tone;
  final Widget leading;
  final Widget? badge;
  final String name;
  final String? line2;
  final String? line3;

  @override
  Widget build(BuildContext context) {
    final ink = TileInk.of(tone);
    final accent = switch (tone) {
      TileTone.navy => UrbColors.lime,
      TileTone.white => UrbColors.blue,
      _ => Colors.white,
    };
    return BentoTile(
      tone: tone,
      padding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 164),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leading,
                const Spacer(),
                ?badge,
              ],
            ),
            const SizedBox(height: 22),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: UrbText.h1.copyWith(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.15,
                    height: 1.12,
                    color: ink.strong,
                  ),
                ),
                if (line2 != null) ...[
                  const SizedBox(height: 4),
                  Text(line2!, style: UrbText.title.copyWith(fontSize: 15, fontWeight: FontWeight.w700, color: accent)),
                ],
                if (line3 != null) ...[
                  const SizedBox(height: 4),
                  Text(line3!, style: UrbText.label.copyWith(fontWeight: FontWeight.w600, color: ink.muted)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum PillTone { lime, dark, ghost, green, blue }

/// Selo curto em pílula (Verificada, Participante, Não reivindicado…).
class TilePill extends StatelessWidget {
  const TilePill(this.label, {super.key, this.tone = PillTone.lime, this.check = false});

  final String label;
  final PillTone tone;
  final bool check;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, checkColor) = switch (tone) {
      PillTone.lime => (UrbColors.lime, UrbColors.navy, UrbColors.navy),
      PillTone.dark => (const Color(0xFF22385A), Colors.white, UrbColors.lime),
      PillTone.ghost => (kSoft, UrbColors.muted, UrbColors.muted),
      PillTone.green => (const Color(0xFFE3F4E7), UrbColors.success, UrbColors.success),
      PillTone.blue => (UrbColors.blueSoft, UrbColors.blue, UrbColors.blue),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: tone == PillTone.ghost ? Border.all(color: UrbColors.line) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (check) ...[
            UrbIcon(UrbIcons.check, size: 12, color: checkColor, strokeWidth: 3.2),
            const SizedBox(width: 5),
          ],
          Text(label, style: UrbText.caption.copyWith(fontSize: 11, fontWeight: FontWeight.w800, color: foreground, height: 1.25)),
        ],
      ),
    );
  }
}

/// Quadrado arredondado com as letras do órgão.
class Monogram extends StatelessWidget {
  const Monogram({super.key, required this.name, this.size = 46, this.background, this.foreground});

  final String name;
  final double size;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final color = background ?? agencyColor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Text(
        agencyMonogram(name),
        style: UrbText.title.copyWith(
          fontSize: size * 0.37,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: foreground ?? onAgencyColor(color),
        ),
      ),
    );
  }
}

/// Iniciais de uma pessoa num círculo (vereadores não têm foto no UrbApp).
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 56, this.background = UrbColors.blue, this.foreground = Colors.white});

  final String name;
  final double size;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Text(
        personInitials(name),
        style: UrbText.title.copyWith(fontSize: size * 0.34, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: foreground),
      ),
    );
  }
}

String personInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, math.min(2, parts.first.length)).toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

const _connectors = {'de', 'da', 'do', 'das', 'dos', 'e'};

/// "SAAE Sorocaba" → SA; "Secretaria de Obras" → SO; "Iluminação Pública" → IP.
String agencyMonogram(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final first = words.first;
  final isAcronym = first.length >= 2 && first.length <= 5 && first == first.toUpperCase();
  if (isAcronym) return first.substring(0, 2);
  final significant = words.where((word) => !_connectors.contains(word.toLowerCase())).toList();
  if (significant.length < 2) return first.substring(0, math.min(2, first.length)).toUpperCase();
  return (significant.first[0] + significant.last[0]).toUpperCase();
}

/// Cor do órgão a partir do que ele cuida, como nos chips de categoria.
Color agencyColor(String name) {
  final key = name.toLowerCase();
  if (key.contains('saae') || key.contains('água') || key.contains('agua') || key.contains('esgoto') || key.contains('sanea')) {
    return UrbColors.blue;
  }
  if (key.contains('ilumin')) return const Color(0xFFFFC93C);
  if (key.contains('serviços públicos') || key.contains('servicos publicos') || key.contains('limpeza')) {
    return const Color(0xFF1A8A7A);
  }
  if (key.contains('não definido') || key.contains('nao definido')) return UrbColors.slate;
  return categoryColor(null, name);
}

Color onAgencyColor(Color background) =>
    background.computeLuminance() > 0.45 ? UrbColors.navy : Colors.white;

/// Selo do perfil institucional: só aparece para quem aderiu.
Widget? institutionalPill(String label, {required bool claimed, bool participant = false, bool onDark = false}) {
  if (!claimed) return TilePill('Não reivindicado', tone: onDark ? PillTone.dark : PillTone.ghost);
  if (participant) return TilePill(label, tone: PillTone.lime, check: true);
  return TilePill(label, tone: onDark ? PillTone.dark : PillTone.green, check: true);
}

// -----------------------------------------------------------------------------
// Controle segmentado (abas dos perfis)
// -----------------------------------------------------------------------------

class BentoSegments extends StatelessWidget {
  const BentoSegments({super.key, required this.labels, required this.selected, required this.onChanged, this.flex});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  /// Peso de cada segmento (rótulos longos ganham mais espaço).
  final List<int>? flex;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFFECEFE8), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++)
            Expanded(
              flex: flex?[index] ?? 10,
              child: Semantics(
                selected: index == selected,
                button: true,
                label: labels[index],
                excludeSemantics: true,
                onTap: () => onChanged(index),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: index == selected ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: index == selected ? UrbColors.line : Colors.transparent),
                    ),
                    child: Text(
                      labels[index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.label.copyWith(
                        fontWeight: index == selected ? FontWeight.w800 : FontWeight.w700,
                        color: index == selected ? UrbColors.ink : UrbColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Notas, títulos de seção e cartões
// -----------------------------------------------------------------------------

/// Nota curta sobre a regra de resolução (cinza, ícone navy com lime).
class RuleNote extends StatelessWidget {
  const RuleNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      decoration: BoxDecoration(color: kSoft, borderRadius: BorderRadius.circular(18)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: UrbColors.navy, shape: BoxShape.circle),
            child: Text('!', style: UrbText.caption.copyWith(fontSize: 11, fontWeight: FontWeight.w800, color: UrbColors.lime, height: 1)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: UrbText.label.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF3B4858), height: 1.38),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(title, style: UrbText.h3.copyWith(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          ),
          if (trailing != null)
            Text(trailing!, style: UrbText.meta.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: UrbColors.muted)),
        ],
      ),
    );
  }
}

/// Cartão branco simples para listas dentro dos perfis.
class BentoCard extends StatelessWidget {
  const BentoCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => BentoTile(padding: padding, child: child);
}

/// Estado vazio dentro de uma aba: bloco cinza com título e explicação.
class SoftEmpty extends StatelessWidget {
  const SoftEmpty({super.key, required this.title, required this.message, this.glyph});

  final String title;
  final String message;
  final Widget? glyph;

  @override
  Widget build(BuildContext context) {
    return BentoTile(
      tone: TileTone.soft,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (glyph != null) ...[glyph!, const SizedBox(height: 14)],
          Text(title, style: UrbText.h3.copyWith(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.22)),
          const SizedBox(height: 8),
          Text(message, style: UrbText.label.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF4B5868), height: 1.45)),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Glifos sólidos
// -----------------------------------------------------------------------------

/// Prédio público: frontão, três colunas e base.
class BuildingGlyph extends StatelessWidget {
  const BuildingGlyph({super.key, this.color = UrbColors.lime, this.width = 44});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(width, width * 40 / 44), painter: _BuildingPainter(color));
}

class _BuildingPainter extends CustomPainter {
  _BuildingPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 44, size.height / 40);
    final paint = Paint()..color = color;
    canvas.drawPath(Path()..moveTo(22, 2)..lineTo(42, 13)..lineTo(2, 13)..close(), paint);
    for (final x in [5.0, 18.5, 32.0]) {
      canvas.drawRRect(RRect.fromLTRBR(x, 16, x + 7, 33, const Radius.circular(2.5)), paint);
    }
    canvas.drawRRect(RRect.fromLTRBR(2, 35, 42, 40, const Radius.circular(2.5)), paint);
  }

  @override
  bool shouldRepaint(_BuildingPainter oldDelegate) => oldDelegate.color != color;
}

/// Três barras sólidas (rankings).
class BarsGlyph extends StatelessWidget {
  const BarsGlyph({super.key, this.color = UrbColors.navy});

  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget bar(double height) => Container(
          width: 12,
          height: height,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        );
    return SizedBox(
      height: 36,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [bar(22), const SizedBox(width: 4), bar(36), const SizedBox(width: 4), bar(14)],
      ),
    );
  }
}

/// Círculos sobrepostos (pessoas).
class PeopleGlyph extends StatelessWidget {
  const PeopleGlyph({super.key});

  @override
  Widget build(BuildContext context) {
    const colors = [UrbColors.blue, UrbColors.navy, UrbColors.line];
    return SizedBox(
      width: 72,
      height: 36,
      child: Stack(
        children: [
          for (var index = colors.length - 1; index >= 0; index--)
            Positioned(
              left: index * 18.0,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors[index],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pontos: um por ocorrência (até [max]), coloridos pela situação.
class DotsGlyph extends StatelessWidget {
  const DotsGlyph({super.key, required this.colors, this.size = 12});

  final List<Color> colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final color in colors)
          Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      ],
    );
  }
}

/// Pontos espalhados (ocorrências no mapa).
class ScatterGlyph extends StatelessWidget {
  const ScatterGlyph({super.key});

  @override
  Widget build(BuildContext context) {
    const dots = [
      (0.0, 14.0, 10.0, UrbColors.blue),
      (16.0, 2.0, 14.0, UrbColors.navy),
      (36.0, 16.0, 9.0, kFaint),
      (52.0, 4.0, 12.0, UrbColors.blue),
      (26.0, 24.0, 8.0, kFaint),
    ];
    return SizedBox(
      width: 66,
      height: 34,
      child: Stack(
        children: [
          for (final (x, y, size, color) in dots)
            Positioned(
              left: x,
              top: y,
              child: Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            ),
        ],
      ),
    );
  }
}

/// Balão navy com check lime: resposta oficial.
class ResponseGlyph extends StatelessWidget {
  const ResponseGlyph({super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(40, 36), painter: _ResponsePainter());
}

class _ResponsePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bubble = Path()
      ..addRRect(RRect.fromLTRBR(0, 0, 40, 28, const Radius.circular(8)))
      ..moveTo(10, 26)
      ..lineTo(9, 36)
      ..lineTo(20, 26)
      ..close();
    canvas.drawPath(bubble, Paint()..color = UrbColors.navy);
    final check = Path()
      ..moveTo(12, 14)
      ..lineTo(17, 19)
      ..lineTo(28, 9);
    canvas.drawPath(
      check,
      Paint()
        ..color = UrbColors.lime
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ResponsePainter oldDelegate) => false;
}

/// Círculo navy com um ícone lime (usado como glifo de bloco).
class RoundGlyph extends StatelessWidget {
  const RoundGlyph(this.icon, {super.key, this.size = 40, this.background = UrbColors.navy, this.color = UrbColors.lime});

  final UrbIcons icon;
  final double size;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: UrbIcon(icon, size: size * 0.45, color: color, strokeWidth: 3),
    );
  }
}

/// Quadrado navy arredondado com ícone lime (ações oficiais).
class ActionGlyph extends StatelessWidget {
  const ActionGlyph(this.icon, {super.key, this.size = 36});

  final UrbIcons icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: UrbColors.navy, borderRadius: BorderRadius.circular(size * 0.3)),
      child: UrbIcon(icon, size: size * 0.5, color: UrbColors.lime, strokeWidth: 2.4),
    );
  }
}

// -----------------------------------------------------------------------------
// Anel de resolução
// -----------------------------------------------------------------------------

/// Anel com a proporção de resolvidas (navy) e em andamento (azul). Até 12
/// ocorrências, cada uma é um segmento; acima disso, os arcos são proporcionais.
class ResolutionRing extends StatelessWidget {
  const ResolutionRing({super.key, required this.total, required this.resolved, required this.active, this.size = 88});

  final int total;
  final int resolved;
  final int active;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(size: Size.square(size), painter: _RingPainter(total, resolved, active)),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.total, this.resolved, this.active);

  final int total;
  final int resolved;
  final int active;

  static const _rest = Color(0xFFE3E7E8);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 16 / 96;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    if (total <= 0) {
      canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = _rest);
      return;
    }
    final parts = <(double, Color)>[];
    if (total <= 12) {
      for (var index = 0; index < total; index++) {
        parts.add((1, index < resolved ? UrbColors.navy : (index < resolved + active ? UrbColors.blue : _rest)));
      }
    } else {
      final rest = math.max(0, total - resolved - active);
      for (final (count, color) in [(resolved, UrbColors.navy), (active, UrbColors.blue), (rest, _rest)]) {
        if (count > 0) parts.add((count.toDouble(), color));
      }
    }
    final sum = parts.fold<double>(0, (value, part) => value + part.$1);
    final gap = parts.length > 1 ? 4 * math.pi / 180 : 0.0;
    var start = -math.pi / 2;
    for (final (weight, color) in parts) {
      final sweep = math.pi * 2 * weight / sum;
      canvas.drawArc(rect, start + gap / 2, math.max(0.01, sweep - gap), false, paint..color = color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.total != total || oldDelegate.resolved != resolved || oldDelegate.active != active;
}

// -----------------------------------------------------------------------------
// Textos
// -----------------------------------------------------------------------------

/// Duração curta para blocos ("< 1 dia", "3,5 dias", "12 dias").
String shortDays(double? seconds) {
  if (seconds == null) return '—';
  final days = seconds / 86400;
  if (days < 1) return '< 1 dia';
  final value = days >= 10 ? days.round().toString() : formatDecimal(days);
  return '$value ${days < 2 ? 'dia' : 'dias'}';
}

/// Duração por extenso para frases ("menos de 1 dia").
String resolutionDaysLabel(double? seconds) {
  final label = shortDays(seconds);
  return label == '< 1 dia' ? 'menos de 1 dia' : label;
}

const _months = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

String monthShort(DateTime date) => _months[date.month - 1];

/// "6 out" (e o ano quando não é o corrente).
String dayMonth(DateTime date) {
  final local = date.toLocal();
  final base = '${local.day} ${monthShort(local)}';
  return local.year == DateTime.now().year ? base : '$base ${local.year}';
}

/// Rótulos curtos das ações oficiais, para títulos de linha.
const officialActionShortLabels = <String, String>{
  'received': 'Recebida',
  'priority': 'Prioridade reconhecida',
  'forwarding': 'Encaminhada ao órgão',
  'request': 'Providência solicitada',
  'official_position': 'Posicionamento oficial',
  'forecast': 'Previsão informada',
  'analysis': 'Em análise técnica',
  'scheduled': 'Agendada',
  'in_progress': 'Em execução',
  'progress_update': 'Andamento atualizado',
  'executed': 'Serviço executado',
  'observation': 'Observação oficial',
  'conclusion': 'Conclusão informada',
};

UrbIcons officialActionIcon(String type) => switch (type) {
      'priority' => UrbIcons.flag,
      'forwarding' || 'request' => UrbIcons.arrow,
      'forecast' || 'scheduled' => UrbIcons.clock,
      'conclusion' || 'executed' => UrbIcons.check,
      'official_position' || 'observation' => UrbIcons.megaphone,
      _ => UrbIcons.building,
    };

UrbIcons councilorActionIcon(String type) => switch (type) {
      'charge' => UrbIcons.megaphone,
      'official_letter' || 'request' => UrbIcons.message,
      'forwarding' || 'agency_contact' => UrbIcons.arrow,
      'visit' || 'verification' => UrbIcons.location,
      'response_received' => UrbIcons.check,
      _ => UrbIcons.pencil,
    };
