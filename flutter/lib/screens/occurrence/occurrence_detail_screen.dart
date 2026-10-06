import 'package:flutter/material.dart';

import '../../app/app_session.dart';
import '../../app/routes.dart';
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../domain/occurrence_status.dart';
import '../../services/institutional_service.dart';
import '../../services/occurrence_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatter.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/occurrence_widgets.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import 'occurrence_sheets.dart';

class _Evidence {
  const _Evidence({
    required this.url,
    required this.author,
    required this.createdAt,
    required this.reportIndex,
  });

  final String url;
  final String author;
  final DateTime createdAt;
  final int reportIndex;
}

class OccurrenceDetailScreen extends StatefulWidget {
  const OccurrenceDetailScreen({
    super.key,
    required this.occurrenceId,
    this.initial,
    this.anchor = DetailAnchor.top,
  });

  final int occurrenceId;
  final Occurrence? initial;
  final DetailAnchor anchor;

  @override
  State<OccurrenceDetailScreen> createState() => _OccurrenceDetailScreenState();
}

class _OccurrenceDetailScreenState extends State<OccurrenceDetailScreen>
    with OccurrenceListSync {
  final _service = OccurrenceService();
  final _institutional = InstitutionalService();
  final _session = AppSession.instance;
  final _activityKey = GlobalKey();
  final _reportsKey = GlobalKey();
  final _commentsKey = GlobalKey();
  final _commentController = TextEditingController();
  final _commentFocus = FocusNode();
  final _pageController = PageController();

  late Occurrence? _occurrence = widget.initial;
  List<OccurrenceReport> _reports = const [];
  List<OccurrenceComment> _comments = const [];
  List<TimelineEvent> _timeline = const [];
  List<OccurrenceFollower> _councilors = const [];
  ResolutionContext? _resolution;
  OccurrenceCapabilities _capabilities = const OccurrenceCapabilities();
  bool _loading = true;
  String? _error;
  bool _aboutExpanded = false;
  bool _reportsExpanded = false;
  bool _historyExpanded = false;
  bool _commentsExpanded = false;
  OccurrenceComment? _replyingTo;
  bool _sendingComment = false;
  int _evidenceIndex = 0;
  bool _anchored = false;

  @override
  void initState() {
    super.initState();
    if (widget.anchor == DetailAnchor.reports) _reportsExpanded = true;
    _load();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocus.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void onOccurrenceChanged(Occurrence occurrence) {
    if (occurrence.id == widget.occurrenceId) {
      setState(() => _occurrence = occurrence);
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final occurrence = await _service.fetchById(widget.occurrenceId);
      if (occurrence == null) {
        if (mounted) {
          setState(() => _error = 'Esta ocorrência não está mais disponível.');
        }
        return;
      }
      final results = await Future.wait<dynamic>([
        _service.fetchReports(occurrence.id),
        _service.fetchComments(occurrence.id),
        _service.fetchTimeline(occurrence.id),
        _service.fetchResolutionContext(occurrence.id),
        _institutional.fetchCouncilorsFollowing(occurrence.id),
        _institutional
            .fetchCapabilities(occurrence)
            .catchError((_) => const OccurrenceCapabilities()),
      ]);
      if (!mounted) return;
      setState(() {
        _occurrence = occurrence;
        _reports = results[0] as List<OccurrenceReport>;
        _comments = results[1] as List<OccurrenceComment>;
        _timeline = results[2] as List<TimelineEvent>;
        _resolution = results[3] as ResolutionContext?;
        _councilors = results[4] as List<OccurrenceFollower>;
        _capabilities = results[5] as OccurrenceCapabilities;
      });
      _session.publish(occurrence);
      _scrollToAnchor();
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToAnchor() {
    if (_anchored || widget.anchor == DetailAnchor.top) return;
    _anchored = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final target =
          (widget.anchor == DetailAnchor.comments ? _commentsKey : _reportsKey)
              .currentContext;
      if (target == null) return;
      await Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
      if (widget.anchor == DetailAnchor.comments) _commentFocus.requestFocus();
    });
  }

  List<_Evidence> get _evidence => [
    for (var index = 0; index < _reports.length; index++)
      for (final image in _reports[index].images)
        _Evidence(
          url: image.url,
          author: _reports[index].publicAuthor,
          createdAt: _reports[index].createdAt,
          reportIndex: _reports.length - index,
        ),
  ];

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    final occurrence = _occurrence;
    if (text.isEmpty || occurrence == null) return;
    setState(() => _sendingComment = true);
    try {
      await _service.addComment(occurrence.id, text, parentId: _replyingTo?.id);
      _commentController.clear();
      final comments = await _service.fetchComments(occurrence.id);
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _replyingTo = null;
      });
      _session.publish(
        occurrence.copyWith(commentsCount: occurrence.commentsCount + 1),
      );
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  Future<void> _toggleLike(OccurrenceComment comment) async {
    final liked = !comment.likedByMe;
    setState(() {
      comment.likedByMe = liked;
      comment.likesCount += liked ? 1 : -1;
    });
    try {
      await _service.setCommentLike(comment.id, liked);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        comment.likedByMe = !liked;
        comment.likesCount += liked ? -1 : 1;
      });
      showUrbToast(context, friendlyError(error));
    }
  }

  void _startReply(OccurrenceComment comment) {
    setState(() => _replyingTo = comment);
    _commentFocus.requestFocus();
  }

  Future<void> _afterAction(bool changed, String message) async {
    if (!changed || !mounted) return;
    showUrbToast(context, message);
    await _load();
  }

  Future<void> _resolutionAction() async {
    final occurrence = _occurrence;
    final resolution = _resolution;
    if (occurrence == null || resolution == null) return;
    if (occurrence.status == OccurrenceStatus.awaitingValidation) {
      await openValidation(context, occurrence);
      await _load();
      return;
    }
    if (occurrence.status == OccurrenceStatus.resolved) {
      final reopened = await showReopenSheet(context, occurrence);
      await _afterAction(reopened, 'Ocorrência reaberta com nova evidência.');
      return;
    }
    final changed = await showResolutionSheet(
      context,
      occurrence: occurrence,
      resolution: resolution,
    );
    await _afterAction(
      changed,
      'Possível resolução informada. A comunidade foi convidada a validar.',
    );
  }

  Future<void> _startFollowing() async {
    final occurrence = _occurrence;
    if (occurrence == null) return;
    try {
      await _institutional.startCouncilorFollowing(occurrence.id);
      await _afterAction(true, 'Você passou a acompanhar esta demanda.');
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    }
  }

  Future<void> _endFollowing() async {
    final followingId = _capabilities.councilorFollowingId;
    if (followingId == null) return;
    final confirmed = await UrbConfirmSheet.show(
      context,
      title: 'Encerrar acompanhamento?',
      message:
          'O encerramento fica registrado publicamente. Você poderá retomar se a ocorrência continuar aberta.',
      confirmLabel: 'Encerrar acompanhamento',
    );
    if (!confirmed) return;
    try {
      await _institutional.endCouncilorFollowing(
        followingId: followingId,
        description: 'Acompanhamento encerrado pelo vereador.',
      );
      await _afterAction(true, 'Acompanhamento encerrado.');
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    }
  }

  Future<void> _registerCouncilorAction() async {
    final occurrence = _occurrence;
    final followingId = _capabilities.councilorFollowingId;
    if (occurrence == null || followingId == null) return;
    await _afterAction(
      await showCouncilorActionSheet(
        context,
        occurrence: occurrence,
        followingId: followingId,
      ),
      'Atuação registrada no histórico público.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final occurrence = _occurrence;
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: UrbSubscreenHeader(
        title: 'Detalhes da ocorrência',
        trailing:
            occurrence != null &&
                _councilorOnly &&
                _capabilities.hasActiveFollowing
            ? UrbSquareButton(
                icon: UrbIcons.more,
                tooltip: 'Opções do acompanhamento',
                size: 36,
                onPressed: _showFollowingOptions,
              )
            : null,
      ),
      bottomNavigationBar:
          occurrence != null &&
              _capabilities.isEligibleCouncilor &&
              !occurrence.status.isFinal
          ? _councilorBottomAction(occurrence)
          : null,
      body: occurrence == null
          ? (_error != null
                ? UrbErrorState(message: _error!, onRetry: _load)
                : const UrbLoadingView())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom + 36,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _layout(occurrence),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  bool get _councilorOnly =>
      _capabilities.isEligibleCouncilor &&
      !_capabilities.canActForAdministration &&
      !_capabilities.canActForAgency;

  /// A mesma ocorrência para todos os papéis, em quatro camadas:
  /// capa (foto, título e prova social), situação com a próxima ação, quem
  /// cuida e atividade (histórico, relatos e comentários numa só área).
  /// O vereador ganha apenas "Seu acompanhamento" e a barra fixa (spec §44.7).
  List<Widget> _layout(Occurrence occurrence) {
    final councilorFollowing =
        _councilorOnly && _capabilities.hasActiveFollowing;
    Widget inset(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: child,
    );
    return [
      _hero(occurrence),
      inset(_titleBlock(occurrence)),
      inset(_socialBar(occurrence)),
      inset(_about(occurrence)),
      inset(_stateCard(occurrence)),
      if (_capabilities.hasAnyRole && !_councilorOnly)
        inset(_roleActions(occurrence)),
      if (councilorFollowing) inset(_councilorFollowing()),
      inset(_responsibles(occurrence)),
      _activity(occurrence),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
    ];
  }

  /// Abre uma aba da atividade e leva a tela até ela.
  Future<void> _openActivityTab(int tab, {bool focusComment = false}) async {
    if (tab == 1) setState(() => _reportsExpanded = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final target = (tab == 1 ? _reportsKey : _commentsKey).currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
    if (focusComment) _commentFocus.requestFocus();
  }

  // ---------------------------------------------------------------------------
  // 1. Capa
  // ---------------------------------------------------------------------------

  Widget _overlayChip(
    String text, {
    Color? background,
    Color? foreground,
    bool pill = false,
  }) => Container(
    padding: EdgeInsets.symmetric(horizontal: pill ? 11 : 10, vertical: 7),
    decoration: BoxDecoration(
      color: background ?? const Color(0xE011233D),
      borderRadius: BorderRadius.circular(pill ? 20 : 8),
    ),
    child: Text(
      text,
      style: UrbText.caption.copyWith(
        color: foreground ?? Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: pill ? 12 : 10.5,
      ),
    ),
  );

  /// Foto de ponta a ponta, com a situação e a categoria sobre a imagem.
  Widget _hero(Occurrence occurrence) {
    final evidence = _evidence;
    const height = 270.0;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (evidence.isEmpty)
            OccurrenceImage(
              url: null,
              categoryName: occurrence.categoryName,
              categorySlug: occurrence.categorySlug,
              height: height,
              width: double.infinity,
              radius: 0,
            )
          else
            PageView.builder(
              controller: _pageController,
              itemCount: evidence.length,
              onPageChanged: (index) => setState(() => _evidenceIndex = index),
              itemBuilder: (context, index) => GestureDetector(
                onTap: () => _openGallery(evidence, index),
                child: Semantics(
                  label: 'Foto ${index + 1} de ${evidence.length}',
                  button: true,
                  child: Image.network(
                    evidence[index].url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Container(color: UrbColors.blueSoft),
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                        ? child
                        : Container(color: UrbColors.blueSoft),
                  ),
                ),
              ),
            ),
          IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: 96,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      const Color(0xFF11233D).withValues(alpha: 0.6),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 14,
            left: 18,
            child: _overlayChip(
              occurrence.categoryName.toUpperCase(),
              background: UrbColors.lime,
              foreground: UrbColors.navy,
            ),
          ),
          if (evidence.length > 1)
            Positioned(
              top: 14,
              right: 18,
              child: _overlayChip('${_evidenceIndex + 1} / ${evidence.length}'),
            )
          else if (evidence.isEmpty && !_loading)
            Positioned(top: 14, right: 18, child: _overlayChip('Sem foto')),
          Positioned(
            left: 18,
            bottom: 16,
            child: _overlayChip(
              occurrence.status.label,
              background: Colors.white,
              foreground: occurrence.status.foreground,
              pill: true,
            ),
          ),
          if (occurrence.administrativePriority)
            Positioned(
              right: 18,
              bottom: 16,
              child: _overlayChip(
                'Prioridade da gestão',
                background: UrbColors.lime,
                foreground: UrbColors.navy,
                pill: true,
              ),
            ),
          if (evidence.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 5,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var index = 0; index < evidence.length; index++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: index == _evidenceIndex ? 14 : 5,
                      height: 4,
                      decoration: BoxDecoration(
                        color: index == _evidenceIndex
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _openGallery(List<_Evidence> evidence, int initial) {
    Navigator.of(context).push(
      urbRoute(
        _EvidenceGallery(evidence: evidence, initial: initial),
        fullscreenDialog: true,
      ),
    );
  }

  Widget _titleBlock(Occurrence occurrence) {
    final distance = _session.distanceTo(occurrence);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              occurrence.title,
              style: UrbText.h1.copyWith(fontSize: 26, height: 1.08),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: UrbIcon(
                  UrbIcons.location,
                  size: 14,
                  color: UrbColors.blue,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  [
                    occurrence.fullAddress.isEmpty
                        ? occurrence.cityName
                        : occurrence.fullAddress,
                    if (distance != null) formatDistance(distance),
                    'Criada ${formatRelativeTime(occurrence.createdAt).toLowerCase()}',
                  ].join(' · '),
                  style: UrbText.meta,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Prova social e ações pessoais (apoiar, comentar, compartilhar). As
  /// ações institucionais ficam em blocos próprios, nunca misturadas aqui.
  Widget _socialBar(Occurrence occurrence) {
    final reportsLabel = plural(
      occurrence.reportsCount,
      'relato cidadão',
      'relatos cidadãos',
    );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: '$reportsLabel. Ver relatos',
            excludeSemantics: true,
            onTap: () => _openActivityTab(1),
            child: InkWell(
              onTap: () => _openActivityTab(1),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    AvatarStack(
                      reports: _reports,
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
            onSupport: () => _session.toggleSupport(context, occurrence),
            onComments: () => _openActivityTab(2, focusComment: true),
            onFollow: () => _session.toggleFollow(context, occurrence),
            onShare: () => _session.share(context, occurrence),
            councilorStatus: _councilorOnly
                ? (_capabilities.councilorFollowingStatus ??
                      (_capabilities.hasActiveFollowing ? 'started' : null))
                : null,
            onCouncilorAction: _councilorOnly && !occurrence.status.isFinal
                ? (_capabilities.hasActiveFollowing
                      ? _endFollowing
                      : _startFollowing)
                : null,
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _about(Occurrence occurrence) {
    final text = occurrence.summary ?? 'Sem descrição adicional.';
    final long = text.length > 190;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            maxLines: long && !_aboutExpanded ? 4 : null,
            overflow: long && !_aboutExpanded ? TextOverflow.ellipsis : null,
            style: UrbText.body.copyWith(color: const Color(0xFF4A5A6E)),
          ),
          if (long)
            UrbTextButton(
              _aboutExpanded ? 'Mostrar menos' : 'Ler descrição completa',
              onPressed: () => setState(() => _aboutExpanded = !_aboutExpanded),
            ),
          if (!occurrence.isMunicipal) ...[
            const SizedBox(height: 14),
            _jurisdictionNotice(occurrence),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Situação e próxima ação
  // ---------------------------------------------------------------------------

  /// O estado do problema e o que fazer a respeito, no mesmo lugar: a trilha
  /// do ciclo em cima e, embaixo, o caminho da resolução (informar, validar,
  /// confirmar). Só a validação da comunidade resolve (spec §30).
  Widget _stateCard(Occurrence occurrence) {
    return Container(
      margin: const EdgeInsets.only(top: 22),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDFE4E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _lifecycleTrack(occurrence),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1),
          ),
          _resolutionBlock(occurrence),
        ],
      ),
    );
  }

  Widget _lifecycleTrack(Occurrence occurrence) {
    final current = occurrence.status.lifecycleIndex;
    if (occurrence.status == OccurrenceStatus.closed) {
      return Text(
        'Encerrada administrativamente. Isso não representa resolução do problema.',
        style: UrbText.bodySmall,
      );
    }
    Color dotColor(int index) => index == current
        ? UrbColors.navy
        : (index < current ? const Color(0xFF9BA8B5) : const Color(0xFFCFD5D6));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            Positioned(
              top: 6,
              left: 30,
              right: 30,
              child: Container(height: 2, color: const Color(0xFFDCE1E1)),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (
                  var index = 0;
                  index < OccurrenceStatus.lifecycle.length;
                  index++
                )
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: index == current
                                ? UrbColors.lime
                                : (index < current
                                      ? const Color(0xFF9BA8B5)
                                      : UrbColors.canvas),
                            border: Border.all(
                              color: dotColor(index),
                              width: index == current ? 2 : 1.6,
                            ),
                            boxShadow: index == current
                                ? [
                                    BoxShadow(
                                      color: UrbColors.lime.withValues(
                                        alpha: 0.3,
                                      ),
                                      spreadRadius: 4,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          OccurrenceStatus.lifecycle[index].label,
                          textAlign: TextAlign.center,
                          style: UrbText.caption.copyWith(
                            fontSize: 10.5,
                            height: 1.25,
                            color: index == current
                                ? UrbColors.navy
                                : const Color(0xFF98A1AA),
                            fontWeight: index == current
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
        if (occurrence.status == OccurrenceStatus.reopened) ...[
          const SizedBox(height: 12),
          Text(
            'Reaberta: uma resolução anterior foi contestada com nova evidência.',
            style: UrbText.caption.copyWith(color: UrbColors.warning),
          ),
        ],
      ],
    );
  }

  Widget _resolutionBlock(Occurrence occurrence) {
    final status = occurrence.status;
    final resolution = _resolution;
    final cycle = resolution?.cycle;
    final required =
        cycle?.confirmationsRequired ?? resolution?.confirmationsRequired ?? 3;
    final radius = resolution?.radiusKm ?? 5.0;
    String title;
    String body;
    String? action;
    var enabled = true;
    var primary = false;
    switch (status) {
      case OccurrenceStatus.resolved:
        title = 'Resolvida pela comunidade';
        body =
            'Moradores próximos confirmaram a resolução. Histórico, relatos e evidências continuam disponíveis; se o problema voltar, ele pode ser reaberto.';
        action = 'Reabrir com nova evidência';
      case OccurrenceStatus.awaitingValidation:
        title = 'Aguardando validação da comunidade';
        body = cycle == null
            ? 'Uma possível resolução foi informada.'
            : '${cycle.initiatorLabel} informou que o problema pode ter sido resolvido. Moradores próximos, em até ${formatDecimal(radius, digits: radius % 1 == 0 ? 0 : 1)} km, confirmam ou contestam.';
        if (cycle?.initiatedByMe ?? false) {
          body =
              '$body Você informou esta possível resolução e não participa da contagem.';
        } else if (cycle?.myVote != null) {
          body = '$body Sua validação já foi registrada.';
        } else {
          action = 'Confirmar situação';
          primary = true;
        }
      case OccurrenceStatus.closed:
        title = 'Ocorrência encerrada';
        body =
            'Encerramentos administrativos não contam como resolução do problema.';
      default:
        title = 'O problema já foi resolvido?';
        body =
            'Quem informar abre a validação da comunidade. A ocorrência só vira resolvida depois que $required moradores próximos, em até ${formatDecimal(radius, digits: radius % 1 == 0 ? 0 : 1)} km, confirmarem.';
        action = 'Informar possível resolução';
        if (resolution?.cooldownUntil != null) {
          enabled = false;
          body =
              'Sua última tentativa não foi confirmada. Você poderá informar novamente em '
              '${formatRemaining(resolution!.cooldownUntil!.difference(DateTime.now()))}.';
        }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: UrbText.title.copyWith(fontSize: 15)),
        if (status == OccurrenceStatus.awaitingValidation && cycle != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              for (var index = 0; index < cycle.confirmationsRequired; index++)
                Expanded(
                  child: Container(
                    height: 5,
                    margin: EdgeInsets.only(
                      right: index == cycle.confirmationsRequired - 1 ? 0 : 5,
                    ),
                    decoration: BoxDecoration(
                      color: index < cycle.confirmations
                          ? UrbColors.blue
                          : const Color(0xFFE1E5F6),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${cycle.confirmations} de ${cycle.confirmationsRequired} confirmações · termina em ${formatRemaining(cycle.remaining)}',
            style: UrbText.caption.copyWith(
              color: UrbColors.blue,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          body,
          style: UrbText.caption.copyWith(fontSize: 12.5, height: 1.45),
        ),
        if (action != null) ...[
          const SizedBox(height: 14),
          UrbButton(
            label: action,
            tone: primary ? UrbButtonTone.blue : UrbButtonTone.outlineBlue,
            expand: true,
            height: 46,
            onPressed: enabled && resolution != null ? _resolutionAction : null,
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Quem cuida
  // ---------------------------------------------------------------------------

  /// Órgão, gestão e vereadores em linhas leves: identificam quem responde
  /// sem virar um painel institucional.
  Widget _responsibles(Occurrence occurrence) {
    final verified = occurrence.agencyStatus.isVerified;
    Widget line({
      required Widget leading,
      required String title,
      required String subtitle,
      VoidCallback? onTap,
      Widget? trailing,
    }) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: UrbText.titleSmall.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(subtitle, style: UrbText.caption),
                ],
              ),
            ),
            ?trailing,
            if (onTap != null)
              const UrbIcon(UrbIcons.chevron, size: 14, color: UrbColors.muted),
          ],
        ),
      ),
    );

    Widget initial(String text, Color color) => Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        text.characters.first.toUpperCase(),
        style: UrbText.label.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Quem cuida disso', style: UrbText.h3),
          const SizedBox(height: 4),
          line(
            leading: initial(occurrence.agencyName ?? 'O', UrbColors.navy),
            title: occurrence.agencyName ?? 'Órgão municipal responsável',
            subtitle: 'Órgão responsável',
            trailing: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: UrbVerificationPill(
                label: occurrence.agencyStatus.label,
                verified: verified,
              ),
            ),
            onTap: occurrence.agencyId == null
                ? null
                : () => openAgency(context, occurrence.agencyId!),
          ),
          const Divider(height: 1),
          line(
            leading: initial(occurrence.cityName, UrbColors.blue),
            title: 'Prefeitura de ${occurrence.cityName}',
            subtitle: 'Gestão municipal',
            onTap: () => openAdministration(
              context,
              administrationId: occurrence.administrationId,
            ),
          ),
          for (final councilor in _councilors) ...[
            const Divider(height: 1),
            line(
              leading: initial(councilor.name, UrbColors.violet),
              title: councilor.name,
              subtitle: [
                'Vereador(a) acompanhando',
                if (councilor.party != null) councilor.party!,
                councilorFollowingStatusLabels[councilor.status] ??
                    'Acompanhando',
              ].join(' · '),
              onTap: () => openCouncilor(context, councilor.councilorProfileId),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            verified
                ? 'Perfil do órgão verificado no UrbApp. Atualizações oficiais aparecem sinalizadas no histórico.'
                : 'Responsável identificado automaticamente pelo UrbApp. Isso não significa que o órgão reconheceu a ocorrência.',
            style: UrbText.caption.copyWith(fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. Atividade: histórico, relatos e comentários da mesma ocorrência
  // ---------------------------------------------------------------------------

  int get _commentTotal => _comments.fold<int>(
    0,
    (sum, comment) => sum + 1 + comment.replies.length,
  );

  Widget _activity(Occurrence occurrence) {
    Widget section(
      Key? key,
      String title,
      int count,
      Widget child, {
      bool first = false,
    }) => Container(
      key: key,
      padding: EdgeInsets.fromLTRB(18, first ? 22 : 20, 18, 22),
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: UrbColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(title, style: UrbText.h3),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: UrbColors.canvas,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: UrbText.caption.copyWith(
                    color: UrbColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
    return Container(
      key: _activityKey,
      margin: const EdgeInsets.only(top: 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border.symmetric(horizontal: BorderSide(color: UrbColors.line)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              section(
                null,
                'Histórico',
                _timeline.length,
                _historyTab(),
                first: true,
              ),
              section(
                _reportsKey,
                'Relatos da comunidade',
                _reports.length,
                _reportsTab(occurrence),
              ),
              section(
                _commentsKey,
                'Comentários',
                _commentTotal,
                _commentsTab(occurrence),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyTab() {
    final visible = _historyExpanded ? _timeline : _timeline.take(4).toList();
    if (_timeline.isEmpty) {
      return Text(
        _loading ? 'Carregando histórico…' : 'Sem eventos registrados.',
        style: UrbText.caption,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < visible.length; index++)
          TimelineTile(
            event: visible[index],
            last: index == visible.length - 1,
            onTap: visible[index].agencyId != null
                ? () => openAgency(context, visible[index].agencyId!)
                : visible[index].councilorProfileId != null
                ? () =>
                      openCouncilor(context, visible[index].councilorProfileId!)
                : null,
          ),
        if (_timeline.length > 4)
          Align(
            alignment: Alignment.centerLeft,
            child: UrbTextButton(
              _historyExpanded ? 'Mostrar menos' : 'Ver histórico completo',
              onPressed: () =>
                  setState(() => _historyExpanded = !_historyExpanded),
            ),
          ),
      ],
    );
  }

  Widget _reportsTab(Occurrence occurrence) {
    final visible = _reportsExpanded ? _reports : _reports.take(3).toList();
    final canAdd =
        occurrence.status.acceptsResolutionReport ||
        occurrence.status == OccurrenceStatus.awaitingValidation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canAdd)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Também viu este problema? Complemente sem criar uma ocorrência duplicada.',
                    style: UrbText.caption,
                  ),
                ),
                const SizedBox(width: 10),
                UrbButton(
                  label: 'Adicionar meu relato',
                  tone: UrbButtonTone.outlineBlue,
                  height: 38,
                  onPressed: () async {
                    final submission = await openReportFlow(
                      context,
                      existing: occurrence,
                    );
                    if (submission != null) _load();
                  },
                ),
              ],
            ),
          ),
        for (final report in visible)
          _ReportTile(
            report: report,
            isMine:
                report.authorId != null &&
                report.authorId == _service.currentUserId,
            onReport: () => _reportContent('post', report.id, report.authorId),
          ),
        if (_reports.length > 3)
          Align(
            alignment: Alignment.centerLeft,
            child: UrbTextButton(
              _reportsExpanded
                  ? 'Mostrar menos relatos'
                  : 'Ver todos os ${_reports.length} relatos',
              onPressed: () =>
                  setState(() => _reportsExpanded = !_reportsExpanded),
            ),
          ),
      ],
    );
  }

  void _reportContent(String type, int id, String? authorId) {
    if (authorId != null && authorId == _service.currentUserId) {
      showUrbToast(context, 'Não é possível denunciar o próprio conteúdo.');
      return;
    }
    showReportContentSheet(context, targetType: type, targetId: id);
  }

  Widget _commentsTab(Occurrence occurrence) {
    final canComment = occurrence.status.acceptsInteraction;
    final visible = _commentsExpanded ? _comments : _comments.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_replyingTo != null)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Respondendo a ${_replyingTo!.authorName}',
                    style: UrbText.caption.copyWith(
                      color: const Color(0xFF687688),
                    ),
                  ),
                ),
                UrbTextButton(
                  'Cancelar',
                  onPressed: () => setState(() => _replyingTo = null),
                ),
              ],
            ),
          ),
        if (canComment)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  focusNode: _commentFocus,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1000,
                  onChanged: (_) => setState(() {}),
                  textCapitalization: TextCapitalization.sentences,
                  style: UrbText.bodySmall.copyWith(color: UrbColors.navy),
                  decoration: InputDecoration(
                    hintText: _replyingTo == null
                        ? 'Escreva um comentário...'
                        : 'Responder a ${_replyingTo!.authorName}...',
                    counterText: '',
                    filled: true,
                    fillColor: UrbColors.canvas,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              UrbButton(
                label: 'Enviar',
                height: 46,
                loading: _sendingComment,
                onPressed: _commentController.text.trim().isEmpty
                    ? null
                    : _sendComment,
              ),
            ],
          )
        else
          Text(
            'Esta ocorrência foi encerrada e não recebe novos comentários.',
            style: UrbText.caption,
          ),
        if (_comments.isEmpty && !_loading)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              'Ninguém comentou ainda. Comece a conversa sobre esta ocorrência.',
              style: UrbText.caption,
            ),
          ),
        for (final comment in visible)
          _CommentThread(
            comment: comment,
            onLike: _toggleLike,
            onReply: canComment ? _startReply : null,
            onReport: (item) =>
                _reportContent('comment', item.id, item.authorId),
            onAuthor: (item) => openUserProfile(context, item.authorId),
          ),
        if (_comments.length > 5)
          Align(
            alignment: Alignment.centerLeft,
            child: UrbTextButton(
              _commentsExpanded
                  ? 'Mostrar menos'
                  : 'Ver todos os $_commentTotal comentários',
              onPressed: () =>
                  setState(() => _commentsExpanded = !_commentsExpanded),
            ),
          ),
      ],
    );
  }

  TimelineEvent? _latestEvent(bool Function(TimelineEvent event) test) {
    TimelineEvent? latest;
    for (final event in _timeline) {
      if (!test(event)) continue;
      if (latest == null || event.createdAt.isAfter(latest.createdAt)) {
        latest = event;
      }
    }
    return latest;
  }

  /// "Seu acompanhamento": bloco compacto, só com o que muda a decisão do
  /// vereador. A ação principal fica na barra fixa.
  Widget _councilorFollowing() {
    final caps = _capabilities;
    final mine = _latestEvent(
      (event) =>
          event.actorKind == 'councilor' &&
          (caps.councilorProfileId == null ||
              event.councilorProfileId == caps.councilorProfileId),
    );
    final official = _latestEvent(
      (event) =>
          event.actorKind == 'agency' || event.actorKind == 'administration',
    );
    final awaiting = caps.councilorFollowingStatus == 'awaiting_response';
    final startedAt = caps.councilorFollowingStartedAt;

    final mineText = mine == null
        ? 'Nenhuma atuação sua ainda'
        : 'Sua última atuação ${formatRelativeTime(mine.createdAt).toLowerCase()}';
    final officialText = official == null
        ? 'sem retorno do órgão'
        : 'retorno do órgão ${formatRelativeTime(official.createdAt).toLowerCase()}';
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: UrbColors.blueSoft.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Seu acompanhamento',
                  style: UrbText.label.copyWith(
                    color: UrbColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                councilorFollowingStatusLabels[caps.councilorFollowingStatus] ??
                    'Em acompanhamento',
                style: UrbText.caption.copyWith(
                  color: awaiting ? UrbColors.warning : UrbColors.blue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (startedAt != null) 'Desde ${formatDate(startedAt)}',
              mineText,
              officialText,
            ].join(' · '),
            style: UrbText.caption.copyWith(
              color: official == null ? UrbColors.warning : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFollowingOptions() async {
    final end = await showUrbSheet<bool>(
      context: context,
      eyebrow: 'Seu acompanhamento',
      title: 'Opções',
      builder: (sheetContext) => UrbSettingsRow(
        label: 'Encerrar acompanhamento',
        destructive: true,
        subtitle: 'Fica registrado no histórico público.',
        onTap: () => Navigator.of(sheetContext).pop(true),
      ),
    );
    if (end == true) await _endFollowing();
  }

  Widget _jurisdictionNotice(Occurrence occurrence) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: UrbColors.warningSoft,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        '${jurisdictionLabel(occurrence.jurisdictionType)}: esta ocorrência não é de competência municipal'
        '${occurrence.externalResponsibleName == null ? '' : ' (responsável: ${occurrence.externalResponsibleName})'}. '
        'Ela não entra nos indicadores da gestão e dos órgãos municipais.',
        style: UrbText.caption.copyWith(color: UrbColors.warning, fontSize: 12),
      ),
    );
  }

  Widget _roleActions(Occurrence occurrence) {
    final caps = _capabilities;
    final buttons = <Widget>[];
    if (caps.canActForAdministration) {
      buttons.add(
        UrbButton(
          label: 'Registrar ação da gestão',
          icon: UrbIcons.building,
          expand: true,
          onPressed: () async => _afterAction(
            await showInstitutionalActionSheet(
              context,
              occurrence: occurrence,
              actor: 'administration',
            ),
            'Ação oficial registrada no histórico.',
          ),
        ),
      );
    }
    if (caps.canActForAgency) {
      buttons.add(
        UrbButton(
          label: 'Publicar atualização oficial',
          icon: UrbIcons.megaphone,
          expand: true,
          onPressed: () async => _afterAction(
            await showInstitutionalActionSheet(
              context,
              occurrence: occurrence,
              actor: 'agency',
            ),
            'Atualização oficial publicada.',
          ),
        ),
      );
    }
    if (caps.isEligibleCouncilor) {
      if (caps.hasActiveFollowing) {
        buttons.add(
          UrbButton(
            label: 'Registrar atuação',
            icon: UrbIcons.pencil,
            expand: true,
            onPressed: _registerCouncilorAction,
          ),
        );
        buttons.add(
          UrbTextButton(
            'Encerrar acompanhamento',
            color: UrbColors.muted,
            onPressed: _endFollowing,
          ),
        );
      } else if (!occurrence.status.isFinal) {
        buttons.add(
          UrbButton(
            label: 'Acompanhar como vereador',
            icon: UrbIcons.building,
            expand: true,
            onPressed: _startFollowing,
          ),
        );
      }
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 22),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: UrbColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const UrbEyebrow('Sua atuação nesta ocorrência'),
          if (caps.isEligibleCouncilor &&
              caps.councilorFollowingStatus != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2EFFF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Acompanhamento · ${councilorFollowingStatusLabels[caps.councilorFollowingStatus] ?? 'Em andamento'}',
                  style: UrbText.caption.copyWith(
                    color: const Color(0xFF493A89),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            caps.isEligibleCouncilor &&
                    !caps.canActForAdministration &&
                    !caps.canActForAgency
                ? 'Acompanhamento e fiscalização. Suas ações aparecem no histórico público e não marcam a ocorrência como resolvida.'
                : 'Ações oficiais ficam registradas com data, papel e descrição. A resolução depende da validação comunitária.',
            style: UrbText.caption.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 12),
          for (final button in buttons) ...[button, const SizedBox(height: 8)],
        ],
      ),
    );
  }

  Widget _councilorBottomAction(Occurrence occurrence) {
    final active = _capabilities.hasActiveFollowing;
    final awaiting =
        _capabilities.councilorFollowingStatus == 'awaiting_response';
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: UrbColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
          child: SizedBox(
            height: 46,
            child: active
                ? Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: awaiting ? UrbColors.orange : UrbColors.blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          councilorFollowingStatusLabels[_capabilities
                                  .councilorFollowingStatus] ??
                              'Em acompanhamento',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: UrbText.label.copyWith(
                            color: UrbColors.navy,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      UrbButton(
                        label: 'Registrar atuação',
                        icon: UrbIcons.pencil,
                        height: 44,
                        onPressed: _registerCouncilorAction,
                      ),
                    ],
                  )
                : UrbButton(
                    label: 'Acompanhar demanda',
                    icon: UrbIcons.building,
                    height: 46,
                    expand: true,
                    onPressed: _startFollowing,
                  ),
          ),
        ),
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.report,
    required this.isMine,
    required this.onReport,
  });

  final OccurrenceReport report;
  final bool isMine;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE7EBEA))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.images.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                report.images.first.url,
                width: 74,
                height: 78,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 74,
                  height: 78,
                  color: UrbColors.canvasAlt,
                ),
              ),
            )
          else
            Container(
              width: 74,
              height: 78,
              decoration: BoxDecoration(
                color: UrbColors.blueSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: const UrbIcon(
                UrbIcons.message,
                size: 22,
                color: UrbColors.blue,
              ),
            ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isMine ? 'Você' : report.publicAuthor,
                        overflow: TextOverflow.ellipsis,
                        style: UrbText.label.copyWith(
                          color: UrbColors.navy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    // O autor continua vendo o próprio relato anônimo; os demais veem "Relato anônimo".
                    if (isMine && report.isAnonymous) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: UrbColors.canvasAlt,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          'Anônimo para outros',
                          style: UrbText.caption.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      formatTimelineDate(report.createdAt),
                      style: UrbText.caption,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  report.description,
                  style: UrbText.bodySmall.copyWith(
                    color: const Color(0xFF5F6F82),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        report.images.isEmpty
                            ? 'Sem fotos'
                            : '${report.images.length} ${report.images.length == 1 ? 'foto' : 'fotos'}',
                        style: UrbText.caption,
                      ),
                    ),
                    if (!isMine)
                      InkWell(
                        onTap: onReport,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            children: [
                              const UrbIcon(
                                UrbIcons.flag,
                                size: 12,
                                color: UrbColors.muted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Denunciar',
                                style: UrbText.caption.copyWith(fontSize: 10.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentThread extends StatelessWidget {
  const _CommentThread({
    required this.comment,
    required this.onLike,
    required this.onReply,
    required this.onReport,
    required this.onAuthor,
  });

  final OccurrenceComment comment;
  final ValueChanged<OccurrenceComment> onLike;
  final ValueChanged<OccurrenceComment>? onReply;
  final ValueChanged<OccurrenceComment> onReport;
  final ValueChanged<OccurrenceComment> onAuthor;

  Widget _card(OccurrenceComment item, {bool reply = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => onAuthor(item),
            child: UrbAvatar(
              name: item.authorName,
              imageUrl: item.authorAvatarUrl,
              size: reply ? 28 : 32,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      item.authorName,
                      style: UrbText.label.copyWith(
                        color: const Color(0xFF26364C),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      ' · ${formatRelativeTime(item.createdAt)}',
                      style: UrbText.caption.copyWith(
                        color: const Color(0xFF96A0AA),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.body,
                  style: UrbText.bodySmall.copyWith(
                    color: const Color(0xFF526277),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    SocialMetaButton(
                      icon: UrbIcons.heart,
                      label: '${item.likesCount}',
                      semanticLabel: '${item.likesCount} curtidas',
                      active: item.likedByMe,
                      onTap: () => onLike(item),
                    ),
                    const SizedBox(width: 10),
                    if (onReply != null)
                      UrbTextButton(
                        'Responder',
                        color: const Color(0xFF7C8896),
                        onPressed: () => onReply!(item),
                      ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Denunciar comentário',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onReport(item),
                      icon: const UrbIcon(
                        UrbIcons.flag,
                        size: 13,
                        color: Color(0xFFA0AAB4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE8ECEB))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _card(comment),
          if (comment.replies.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 41, bottom: 6),
              padding: const EdgeInsets.only(left: 13),
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: Color(0xFFDCE2E2))),
              ),
              child: Column(
                children: [
                  for (final reply in comment.replies)
                    _card(reply, reply: true),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EvidenceGallery extends StatefulWidget {
  const _EvidenceGallery({required this.evidence, required this.initial});

  final List<_Evidence> evidence;
  final int initial;

  @override
  State<_EvidenceGallery> createState() => _EvidenceGalleryState();
}

class _EvidenceGalleryState extends State<_EvidenceGallery> {
  late int _index = widget.initial;
  late final _controller = PageController(initialPage: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.evidence[_index];
    return Scaffold(
      backgroundColor: const Color(0xFF071427),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Fechar',
                      style: UrbText.label.copyWith(color: Colors.white),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Evidência ${_index + 1} de ${widget.evidence.length}',
                      textAlign: TextAlign.center,
                      style: UrbText.label.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 72),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.evidence.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) => InteractiveViewer(
                  child: Image.network(
                    widget.evidence[index].url,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              color: const Color(0xEB040D1B),
              padding: const EdgeInsets.fromLTRB(18, 17, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.author,
                          style: UrbText.label.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        formatTimelineDate(item.createdAt),
                        style: UrbText.caption.copyWith(
                          color: const Color(0xFF9BA7B7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Relato ${item.reportIndex.toString().padLeft(2, '0')} · Evidência vinculada ao relato cidadão',
                    style: UrbText.caption.copyWith(
                      color: const Color(0xFF9BA7B7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
