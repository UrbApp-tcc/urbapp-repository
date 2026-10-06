import 'package:flutter/material.dart';

import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../domain/occurrence_status.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatter.dart';
import 'urb_components.dart';
import 'urb_icon.dart';

/// Imagem de ocorrência com placeholder geométrico na cor da categoria.
class OccurrenceImage extends StatelessWidget {
  const OccurrenceImage({
    super.key,
    required this.url,
    required this.categoryName,
    this.categorySlug,
    this.width,
    this.height,
    this.radius = 10,
  });

  final String? url;
  final String categoryName;
  final String? categorySlug;
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(categorySlug, categoryName);
    final placeholder = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.16),
            color.withValues(alpha: 0.05),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: UrbIcon(
        UrbIcons.location,
        size: (height ?? 60) * 0.32,
        color: color.withValues(alpha: 0.7),
      ),
    );
    if (url == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        url!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : placeholder,
      ),
    );
  }
}

/// Status em texto com ponto lime (linhas de lista).
class MiniStatus extends StatelessWidget {
  const MiniStatus(this.status, {super.key});

  final OccurrenceStatus status;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: status == OccurrenceStatus.resolved
                ? UrbColors.success
                : UrbColors.lime,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: UrbColors.lime.withValues(alpha: 0.3),
                spreadRadius: 2,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          status.label,
          style: UrbText.caption.copyWith(
            color: const Color(0xFF657487),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// Acompanhamento institucional ativo (não encerrado nem resolvido).
bool isActiveCouncilorFollowing(String? status) =>
    status != null && status != 'ended' && status != 'resolved';

/// Pílula de status com cores semânticas (perfil, prévias).
class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key, this.compact = false});

  final OccurrenceStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: BorderRadius.circular(compact ? 5 : 7),
      ),
      child: Text(
        status.label,
        style: UrbText.caption.copyWith(
          color: status.foreground,
          fontSize: compact ? 10.5 : 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class SocialMetaButton extends StatelessWidget {
  const SocialMetaButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.activeColor = UrbColors.support,
    this.semanticLabel,
  });

  final UrbIcons icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final Color activeColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final color = active ? activeColor : const Color(0xFF748191);
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                UrbIcon(
                  icon,
                  size: 14,
                  color: color,
                  filled: active && icon == UrbIcons.heart,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: UrbText.caption.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Faz o filho ocupar a largura inteira da tela, saindo do recuo lateral da
/// lista (o fio separador cruza a tela; o conteúdo mantém o próprio recuo).
class FullBleed extends StatelessWidget {
  const FullBleed({super.key, required this.child, this.bleed = 18});

  final Widget child;

  /// Recuo lateral da lista que o filho deve atravessar.
  final double bleed;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => UnconstrainedBox(
      constrainedAxis: Axis.vertical,
      child: SizedBox(width: constraints.maxWidth + bleed * 2, child: child),
    ),
  );
}

/// Linha de ocorrência do feed e da busca, corrida como um feed: sem caixa em
/// volta, só um fio fino entre itens. Hierarquia: situação (e há quanto tempo),
/// título, onde, e só então as métricas sociais.
class OccurrenceRow extends StatelessWidget {
  const OccurrenceRow({
    super.key,
    required this.occurrence,
    required this.onOpen,
    this.onReports,
    this.onComments,
    this.onSupport,
    this.trending = false,
    this.distanceKm,
    this.last = false,
    this.councilorStatus,
    this.onCouncilorAction,
    this.horizontalInset = 0,
  });

  /// Recuo do conteúdo quando a linha está dentro de um [FullBleed].
  final double horizontalInset;

  final Occurrence occurrence;
  final VoidCallback onOpen;
  final VoidCallback? onReports;
  final VoidCallback? onComments;
  final VoidCallback? onSupport;
  final bool trending;
  final double? distanceKm;
  final bool last;
  final String? councilorStatus;
  final VoidCallback? onCouncilorAction;

  @override
  Widget build(BuildContext context) {
    final place = [
      occurrence.locationLabel,
      occurrence.categoryName,
    ].where((part) => part.trim().isNotEmpty).join(' · ');
    final where = distanceKm == null
        ? place
        : '${formatDistance(distanceKm!)} · $place';
    final following = isActiveCouncilorFollowing(councilorStatus);
    return Semantics(
      button: true,
      label: '${occurrence.title}, ${occurrence.status.label}',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onOpen,
          child: Container(
            decoration: BoxDecoration(
              border: last
                  ? null
                  : const Border(bottom: BorderSide(color: Color(0xFFE3E7E8))),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalInset,
                vertical: 14,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OccurrenceImage(
                    url: occurrence.primaryImageUrl,
                    categoryName: occurrence.categoryName,
                    categorySlug: occurrence.categorySlug,
                    width: 92,
                    height: 118,
                    radius: 12,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1, right: 2),
                          child: Row(
                            children: [
                              StatusPill(occurrence.status, compact: true),
                              const Spacer(),
                              Text(
                                trending
                                    ? occurrence.trendLabel
                                    : formatRelativeTime(occurrence.createdAt),
                                style: UrbText.caption.copyWith(
                                  color: trending
                                      ? UrbColors.blue
                                      : const Color(0xFF8A96A5),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          occurrence.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: UrbText.title.copyWith(
                            fontSize: 15.5,
                            height: 1.2,
                            color: const Color(0xFF0B1A30),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            const UrbIcon(
                              UrbIcons.location,
                              size: 12,
                              color: UrbColors.muted,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                where,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: UrbText.meta.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SocialMetaButton(
                              icon: UrbIcons.list,
                              label: formatCount(occurrence.reportsCount),
                              semanticLabel: plural(
                                occurrence.reportsCount,
                                'relato',
                                'relatos',
                              ),
                              onTap: onReports ?? onOpen,
                            ),
                            SocialMetaButton(
                              icon: UrbIcons.heart,
                              label: formatCount(occurrence.supportsCount),
                              semanticLabel: plural(
                                occurrence.supportsCount,
                                'apoio',
                                'apoios',
                              ),
                              active: occurrence.supportedByMe,
                              onTap: onSupport,
                            ),
                            SocialMetaButton(
                              icon: UrbIcons.message,
                              label: formatCount(occurrence.commentsCount),
                              semanticLabel: plural(
                                occurrence.commentsCount,
                                'comentário',
                                'comentários',
                              ),
                              onTap: onComments ?? onOpen,
                            ),
                            if (onCouncilorAction != null)
                              SocialMetaButton(
                                icon: UrbIcons.building,
                                label: following
                                    ? 'Acompanhando'
                                    : 'Acompanhar',
                                active: following,
                                activeColor: UrbColors.blue,
                                onTap: onCouncilorAction,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Card em destaque da Home. A foto manda: a situação vira um selo sobre a
/// imagem, o título abre o card e a prova social (relatos e apoios) fica numa
/// linha, sem caixas empilhadas.
class FeaturedOccurrenceCard extends StatelessWidget {
  const FeaturedOccurrenceCard({
    super.key,
    required this.occurrence,
    required this.onOpen,
    required this.onReports,
    required this.onComments,
    required this.onSupport,
    required this.onFollow,
    required this.onShare,
    this.distanceKm,
    this.councilorStatus,
    this.onCouncilorAction,
    this.reporters = const [],
    this.fullBleed = false,
  });

  /// Ocupa toda a largura da tela: sem cantos arredondados nem bordas laterais.
  final bool fullBleed;

  final Occurrence occurrence;
  final VoidCallback onOpen;
  final VoidCallback onReports;
  final VoidCallback onComments;
  final VoidCallback? onSupport;
  final VoidCallback? onFollow;
  final VoidCallback onShare;
  final double? distanceKm;
  final String? councilorStatus;
  final VoidCallback? onCouncilorAction;

  /// Autores dos relatos (já respeitando o anonimato), para as miniaturas.
  final List<OccurrenceReport> reporters;

  Widget _overlayChip(String text, {Color? background, Color? foreground}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: background ?? const Color(0xE011233D),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: UrbText.caption.copyWith(
            color: foreground ?? Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 10.5,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final official = occurrence.latestOfficialAction;
    final reportsLabel = plural(
      occurrence.reportsCount,
      'relato cidadão',
      'relatos cidadãos',
    );
    return Container(
      decoration: fullBleed
          ? const BoxDecoration(
              color: Colors.white,
              border: Border.symmetric(
                horizontal: BorderSide(color: Color(0xFFDFE4E5)),
              ),
            )
          : BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(UrbRadius.lg),
              border: Border.all(color: const Color(0xFFDFE4E5)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A122234),
                  blurRadius: 30,
                  offset: Offset(0, 8),
                ),
              ],
            ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: onOpen,
            child: Stack(
              children: [
                OccurrenceImage(
                  url: occurrence.primaryImageUrl,
                  categoryName: occurrence.categoryName,
                  categorySlug: occurrence.categorySlug,
                  height: 200,
                  width: double.infinity,
                  radius: 0,
                ),
                // Gradiente curto para dar leitura ao selo de situação.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 74,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          const Color(0xFF11233D).withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: _overlayChip(
                    occurrence.categoryName.toUpperCase(),
                    background: UrbColors.lime,
                    foreground: UrbColors.navy,
                  ),
                ),
                if (occurrence.imageCount > 0)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _overlayChip(
                      '${occurrence.imageCount} ${occurrence.imageCount == 1 ? 'foto' : 'fotos'}',
                    ),
                  ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          occurrence.status.label,
                          style: UrbText.caption.copyWith(
                            color: occurrence.status.foreground,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onOpen,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          occurrence.title,
                          style: UrbText.h3.copyWith(
                            fontSize: 19,
                            color: const Color(0xFF0B1A30),
                            height: 1.15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: UrbIcon(
                          UrbIcons.chevron,
                          size: 18,
                          color: UrbColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const UrbIcon(
                      UrbIcons.location,
                      size: 14,
                      color: UrbColors.blue,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        [
                          occurrence.locationLabel,
                          if (distanceKm != null) formatDistance(distanceKm!),
                          formatRelativeTime(occurrence.createdAt),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: UrbText.meta,
                      ),
                    ),
                  ],
                ),
                if (official != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                    decoration: BoxDecoration(
                      color: UrbColors.blueSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          margin: const EdgeInsets.only(top: 1),
                          decoration: const BoxDecoration(
                            color: UrbColors.blue,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const UrbIcon(
                            UrbIcons.check,
                            size: 11,
                            color: Colors.white,
                            strokeWidth: 2.4,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${official.actorLabel} · ${formatRelativeTime(official.createdAt).toLowerCase()}',
                                style: UrbText.caption.copyWith(
                                  color: UrbColors.blue,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                official.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: UrbText.meta.copyWith(
                                  color: const Color(0xFF4A5A6E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Semantics(
                  button: true,
                  label: '$reportsLabel. Ver relatos',
                  excludeSemantics: true,
                  onTap: onReports,
                  child: InkWell(
                    onTap: onReports,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          AvatarStack(
                            reports: reporters,
                            total: occurrence.reportsCount,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              reportsLabel,
                              style: UrbText.label.copyWith(
                                color: const Color(0xFF26364D),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            'Ver relatos',
                            style: UrbText.caption.copyWith(
                              color: UrbColors.blue,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          const UrbIcon(
                            UrbIcons.chevron,
                            size: 14,
                            color: UrbColors.blue,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 6),
                OccurrenceActionBar(
                  occurrence: occurrence,
                  onSupport: onSupport,
                  onComments: onComments,
                  onFollow: onFollow,
                  onShare: onShare,
                  councilorStatus: councilorStatus,
                  onCouncilorAction: onCouncilorAction,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Quem relatou o problema: até 3 rostos sobrepostos e, a partir do quarto
/// relato, um "+N". Relato anônimo aparece como círculo neutro, sem rosto nem
/// iniciais (spec §37). Enquanto os autores não chegam, mostra só círculos
/// neutros, nunca rostos inventados.
class AvatarStack extends StatelessWidget {
  const AvatarStack({super.key, this.reports = const [], this.total = 0});

  final List<OccurrenceReport> reports;
  final int total;

  static const _size = 22.0;
  static const _step = 14.0;
  static const _maxFaces = 3;

  @override
  Widget build(BuildContext context) {
    final count = total > 0 ? total : reports.length;
    final faces = count < _maxFaces ? count : _maxFaces;
    final extra = count - _maxFaces;
    final slots = faces + (extra > 0 ? 1 : 0);
    if (slots == 0) return const SizedBox(width: 0, height: _size);
    return Semantics(
      label: count == 1 ? '1 relato' : '$count relatos',
      excludeSemantics: true,
      child: SizedBox(
        width: _size + (slots - 1) * _step,
        height: _size,
        child: Stack(
          children: [
            for (var index = 0; index < faces; index++)
              Positioned(
                left: index * _step,
                child: _face(
                  index < reports.length ? reports[index] : null,
                  index,
                ),
              ),
            if (extra > 0)
              Positioned(
                left: faces * _step,
                child: _ring(
                  child: Text(
                    '+$extra',
                    style: UrbText.caption.copyWith(
                      color: UrbColors.blue,
                      fontSize: extra > 9 ? 8 : 9.5,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  color: UrbColors.blueSoft,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _ring({required Widget child, Color? color}) => Container(
    width: _size,
    height: _size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
    ),
    child: child,
  );

  Widget _face(OccurrenceReport? report, int index) {
    final hidden =
        report == null || (report.isAnonymous && report.authorId == null);
    if (hidden) {
      return _ring(
        color: const Color(0xFFC9D1DC),
        child: report == null
            ? const SizedBox.shrink()
            : const UrbIcon(UrbIcons.profile, size: 11, color: Colors.white),
      );
    }
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: ClipOval(
        child: UrbAvatar(
          name: report.authorName,
          imageUrl: report.authorAvatarUrl,
          size: _size - 4,
          rounded: false,
          gradientSeed: index,
        ),
      ),
    );
  }
}

/// Apoiar · Comentários · Atualizações · Compartilhar. Para o vereador,
/// "Atualizações" dá lugar ao acompanhamento institucional da demanda, que
/// já notifica as mudanças.
class OccurrenceActionBar extends StatelessWidget {
  const OccurrenceActionBar({
    super.key,
    required this.occurrence,
    required this.onSupport,
    required this.onComments,
    required this.onFollow,
    required this.onShare,
    this.councilorStatus,
    this.onCouncilorAction,
  });

  final Occurrence occurrence;
  final VoidCallback? onSupport;
  final VoidCallback onComments;
  final VoidCallback? onFollow;
  final VoidCallback onShare;
  final String? councilorStatus;
  final VoidCallback? onCouncilorAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionChip(
            icon: UrbIcons.heart,
            value: formatCount(occurrence.supportsCount),
            label: occurrence.supportsCount == 1 ? 'Apoio' : 'Apoios',
            // Fundo igual ao dos outros botões; o vermelho só marca quem já apoiou.
            color: occurrence.supportedByMe ? UrbColors.support : null,
            filled: occurrence.supportedByMe,
            onTap: onSupport,
            tooltip: occurrence.contributedByMe
                ? 'Você contribuiu com esta ocorrência'
                : (occurrence.supportedByMe ? 'Remover apoio' : 'Apoiar'),
          ),
        ),
        Expanded(
          child: _ActionChip(
            icon: UrbIcons.message,
            value: formatCount(occurrence.commentsCount),
            label: occurrence.commentsCount == 1 ? 'Comentário' : 'Comentários',
            onTap: onComments,
            tooltip: 'Comentários',
          ),
        ),
        if (onCouncilorAction != null)
          Expanded(
            child: _ActionChip(
              icon: UrbIcons.building,
              label: isActiveCouncilorFollowing(councilorStatus)
                  ? 'Acompanhando'
                  : 'Acompanhar',
              color: isActiveCouncilorFollowing(councilorStatus)
                  ? UrbColors.blue
                  : null,
              background: isActiveCouncilorFollowing(councilorStatus)
                  ? UrbColors.blueSoft
                  : null,
              onTap: onCouncilorAction,
              tooltip: isActiveCouncilorFollowing(councilorStatus)
                  ? 'Você acompanha esta demanda'
                  : 'Acompanhar demanda',
            ),
          )
        else
          Expanded(
            child: _ActionChip(
              icon: UrbIcons.bookmark,
              label: occurrence.followedByMe ? 'Recebendo' : 'Atualizações',
              color: occurrence.followedByMe ? UrbColors.blue : null,
              background: occurrence.followedByMe ? UrbColors.blueSoft : null,
              filled: occurrence.followedByMe,
              onTap: onFollow,
              tooltip: occurrence.followedByMe
                  ? 'Parar de receber atualizações'
                  : 'Receber atualizações desta ocorrência',
            ),
          ),
        Expanded(
          child: _ActionChip(
            icon: UrbIcons.share,
            label: 'Compartilhar',
            onTap: onShare,
            tooltip: 'Compartilhar',
          ),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.tooltip,
    this.value,
    this.color,
    this.background,
    this.filled = false,
  });

  final UrbIcons icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final String tooltip;
  final Color? color;
  final Color? background;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? const Color(0xFF758191);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background ?? Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                UrbIcon(icon, size: 19, color: foreground, filled: filled),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (value != null)
                          TextSpan(
                            text: '$value ',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        TextSpan(text: label),
                      ],
                    ),
                    maxLines: 1,
                    style: UrbText.caption.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Linha compacta usada em perfis e históricos (imagem 60×60 + pílula de status).
class CompactOccurrenceRow extends StatelessWidget {
  const CompactOccurrenceRow({
    super.key,
    required this.occurrence,
    required this.onTap,
    this.role,
    this.anonymous = false,
    this.trailing,
    this.pill,
  });

  final Occurrence occurrence;
  final VoidCallback onTap;
  final String? role;
  final bool anonymous;
  final Widget? trailing;
  final Widget? pill;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: UrbColors.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OccurrenceImage(
                url: occurrence.primaryImageUrl,
                categoryName: occurrence.categoryName,
                categorySlug: occurrence.categorySlug,
                width: 60,
                height: 60,
                radius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      occurrence.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.titleSmall.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${occurrence.categoryName} · ${occurrence.locationLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.caption,
                    ),
                    const SizedBox(height: 7),
                    pill ?? StatusPill(occurrence.status, compact: true),
                    if (role != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        role!,
                        style: UrbText.caption.copyWith(
                          color: const Color(0xFF4E6070),
                        ),
                      ),
                    ],
                    if (anonymous) ...[
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F3F5),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const UrbIcon(
                              UrbIcons.eyeOff,
                              size: 11,
                              color: UrbColors.muted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Publicado anonimamente · só você vê',
                              style: UrbText.caption.copyWith(fontSize: 10.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton de carregamento para listas de ocorrências (mesmo formato do card).
class OccurrenceListSkeleton extends StatelessWidget {
  const OccurrenceListSkeleton({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height, {double radius = 6}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFEBEDFA),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    return Semantics(
      label: 'Carregando ocorrências',
      child: Column(
        children: List.generate(
          count,
          (_) => Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE3E7E8))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(92, 118, radius: 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(64, 18, radius: 5),
                      const SizedBox(height: 10),
                      bar(double.infinity, 14),
                      const SizedBox(height: 6),
                      bar(150, 14),
                      const SizedBox(height: 10),
                      bar(120, 10),
                      const SizedBox(height: 14),
                      bar(96, 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Evento da linha do tempo pública com ponto colorido por tipo de ator.
class TimelineTile extends StatelessWidget {
  const TimelineTile({
    super.key,
    required this.event,
    this.last = false,
    this.onTap,
  });

  final TimelineEvent event;
  final bool last;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (fill, ring) = switch (event.kind) {
      TimelineKind.official => (UrbColors.blue, UrbColors.blue),
      TimelineKind.community => (UrbColors.lime, const Color(0xFF9EBA42)),
      TimelineKind.councilor => (UrbColors.violet, UrbColors.violet),
      TimelineKind.validation => (UrbColors.navy, UrbColors.navy),
      TimelineKind.moderation => (UrbColors.danger, UrbColors.danger),
      TimelineKind.platform => (
        const Color(0xFF95A2AF),
        const Color(0xFF95A2AF),
      ),
    };
    return InkWell(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 20,
              child: Column(
                children: [
                  const SizedBox(height: 3),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: fill,
                      shape: BoxShape.circle,
                      border: Border.all(color: UrbColors.canvas, width: 3),
                      boxShadow: [BoxShadow(color: ring, spreadRadius: 1)],
                    ),
                  ),
                  if (!last)
                    Expanded(
                      child: Container(
                        width: 1,
                        color: const Color(0xFFDCE1E1),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatTimelineDate(event.createdAt),
                      style: UrbText.caption.copyWith(
                        color: const Color(0xFF96A0AA),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      event.title,
                      style: UrbText.label.copyWith(
                        color: const Color(0xFF28384E),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (event.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        event.description,
                        style: UrbText.meta.copyWith(
                          color: const Color(0xFF738091),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (event.kind == TimelineKind.official) ...[
                      const SizedBox(height: 5),
                      const UrbVerificationPill(label: 'Informação oficial'),
                    ],
                    if (event.evidenceUrl != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          event.evidenceUrl!,
                          height: 90,
                          width: 140,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
