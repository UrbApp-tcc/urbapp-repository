import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_session.dart';
import '../../app/routes.dart';
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../logic/app_rules.dart';
import '../../services/location_service.dart';
import '../../services/institutional_service.dart';
import '../../services/occurrence_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/occurrence_widgets.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import 'location_picker_screen.dart';

enum _Step {
  category,
  evidence,
  review,
  checking,
  similar,
  successNew,
  successAdded,
}

/// Fluxo Relatar (Figma): categoria e local → evidências → revisão →
/// verificação de duplicidade → nova ocorrência ou relato adicionado.
/// Título sugerido a partir da primeira frase da descrição (editável).
String suggestReportTitle(String description) {
  var text = description.trim().split(RegExp(r'[.!?\n]')).first.trim();
  if (text.isEmpty) return '';
  if (text.length > 60) {
    final cut = text.substring(0, 60);
    final space = cut.lastIndexOf(' ');
    text = space > 25 ? cut.substring(0, space) : cut;
  }
  text = text.replaceAll(RegExp(r'[,;:\-–\s]+$'), '');
  return text[0].toUpperCase() + text.substring(1);
}

class ReportFlowScreen extends StatefulWidget {
  const ReportFlowScreen({super.key, this.existingOccurrence});

  /// Quando informado, o relato é adicionado a esta ocorrência (sem duplicar).
  final Occurrence? existingOccurrence;

  @override
  State<ReportFlowScreen> createState() => _ReportFlowScreenState();
}

class _ReportFlowScreenState extends State<ReportFlowScreen> {
  static const _maxPhotos = 4;

  final _service = OccurrenceService();
  final _location = const LocationService();
  final _picker = ImagePicker();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  late _Step _step = widget.existingOccurrence == null
      ? _Step.category
      : _Step.evidence;
  List<CategoryOption> _categories = const [];
  CategoryOption? _category;
  GeoPoint? _point;
  ResolvedAddress? _address;
  CityOption? _city;
  bool _locating = false;
  String? _locationError;
  final List<XFile> _photos = [];
  bool _titleEdited = false;
  bool _anonymous = false;
  InstitutionalAccess _institutionalAccess = const InstitutionalAccess();
  bool _followAsCouncilor = false;
  bool _councilorFollowingStarted = false;
  String? _councilorFollowingWarning;
  List<DuplicateCandidate> _candidates = const [];
  ReportSubmission? _submission;
  Occurrence? _targetOccurrence;
  bool _submitting = false;

  bool get _addingToExisting => widget.existingOccurrence != null;
  int? get _reportCityId => widget.existingOccurrence?.cityId ?? _city?.id;
  bool get _canOfferCouncilorFollowing =>
      !_anonymous &&
      _institutionalAccess.isCouncilor &&
      _reportCityId != null &&
      _institutionalAccess.councilor?.cityId == _reportCityId;
  bool get _hasData =>
      _category != null ||
      _descriptionController.text.trim().isNotEmpty ||
      _photos.isNotEmpty;

  @override
  void initState() {
    super.initState();
    InstitutionalService()
        .fetchMyAccess()
        .then((access) {
          if (mounted) setState(() => _institutionalAccess = access);
        })
        .catchError((_) {});
    if (!_addingToExisting) {
      _service
          .fetchCategories()
          .then((value) {
            if (mounted) setState(() => _categories = value);
          })
          .catchError((Object error) {
            if (mounted) showUrbToast(context, friendlyError(error));
          });
      _detectLocation();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _detectLocation() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final point = await _location.currentPosition();
      await _applyLocation(point, await _location.reverseGeocode(point));
    } catch (error) {
      final fallback = AppSession.instance.position.value;
      if (fallback != null) {
        await _applyLocation(
          fallback,
          await _location.reverseGeocode(fallback),
        );
      } else if (mounted) {
        setState(() => _locationError = friendlyError(error));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _applyLocation(GeoPoint point, ResolvedAddress address) async {
    final session = AppSession.instance;
    if (session.cities.isEmpty) await session.init();
    final matched = _location.matchCity(session.cities, address);
    if (!mounted) return;
    setState(() {
      _point = point;
      _address = address;
      _city = matched;
      _locationError = matched == null
          ? 'O UrbApp ainda não atende a cidade deste local.'
          : null;
    });
  }

  Future<void> _adjustLocation() async {
    final start =
        _point ??
        AppSession.instance.position.value ??
        const GeoPoint(-23.5015, -47.4526);
    final picked = await Navigator.of(context).push<PickedLocation>(
      urbRoute(LocationPickerScreen(initial: start, initialAddress: _address)),
    );
    if (picked != null) await _applyLocation(picked.point, picked.address);
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= _maxPhotos) return;
    final source = kIsWeb
        ? ImageSource.gallery
        : await showModalBottomSheet<ImageSource>(
            context: context,
            backgroundColor: Colors.white,
            builder: (sheetContext) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const UrbIcon(
                      UrbIcons.camera,
                      color: UrbColors.navy,
                    ),
                    title: const Text('Tirar foto agora'),
                    onTap: () =>
                        Navigator.of(sheetContext).pop(ImageSource.camera),
                  ),
                  ListTile(
                    leading: const UrbIcon(
                      UrbIcons.list,
                      color: UrbColors.navy,
                    ),
                    title: const Text('Escolher da galeria'),
                    onTap: () =>
                        Navigator.of(sheetContext).pop(ImageSource.gallery),
                  ),
                ],
              ),
            ),
          );
    if (source == null) return;
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 82,
      );
      if (file != null && mounted) setState(() => _photos.add(file));
    } catch (error) {
      if (mounted) showUrbToast(context, 'Não foi possível acessar as fotos.');
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasData) return true;
    return UrbConfirmSheet.show(
      context,
      title: 'Descartar relato?',
      message: 'As informações que você preencheu serão perdidas.',
      confirmLabel: 'Descartar',
      cancelLabel: 'Continuar relatando',
      destructive: true,
    );
  }

  Future<void> _back() async {
    switch (_step) {
      case _Step.category:
        if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
      case _Step.evidence:
        if (_addingToExisting) {
          if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
        } else {
          setState(() => _step = _Step.category);
        }
      case _Step.review:
        setState(() => _step = _Step.evidence);
      case _Step.similar:
        setState(() => _step = _Step.review);
      default:
        Navigator.of(context).pop(_submission);
    }
  }

  /// Mantém o título acompanhando a descrição enquanto a pessoa não o editar.
  void _onDescriptionChanged(String value) {
    if (!_addingToExisting && !_titleEdited) {
      _titleController.text = suggestReportTitle(value);
    }
    setState(() {});
  }

  /// Nova ocorrência exige foto e descrição; relato adicional só descrição.
  bool get _canReview =>
      _descriptionController.text.trim().length >= 10 &&
      (_addingToExisting ||
          (_photos.isNotEmpty && _titleController.text.trim().length >= 3));

  String _generatedTitle() {
    final typed = _titleController.text.trim();
    if (typed.length >= 3) return typed;
    final place = _address?.street ?? _address?.neighborhood;
    final base =
        _category?.name ??
        widget.existingOccurrence?.categoryName ??
        'Problema urbano';
    return place == null ? base : '$base · $place';
  }

  Future<void> _submitForCheck() async {
    if (_addingToExisting) {
      await _submitToExisting(widget.existingOccurrence!);
      return;
    }
    setState(() => _step = _Step.checking);
    try {
      final candidates = await _service.findPotentialDuplicates(
        cityId: _city!.id,
        categoryId: _category!.id,
        latitude: _point!.latitude,
        longitude: _point!.longitude,
        text: _descriptionController.text
            .trim()
            .split(RegExp(r'\s+'))
            .take(3)
            .join(' '),
      );
      if (!mounted) return;
      if (candidates.isEmpty) {
        await _createNew();
      } else {
        setState(() {
          _candidates = candidates;
          _step = _Step.similar;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _step = _Step.review);
      showUrbToast(context, friendlyError(error));
    }
  }

  Future<void> _createNew() async {
    setState(() {
      _submitting = true;
      _step = _Step.checking;
    });
    try {
      final submission = await _service.createOccurrence(
        cityId: _city!.id,
        categoryId: _category!.id,
        title: _generatedTitle(),
        description: _descriptionController.text,
        latitude: _point!.latitude,
        longitude: _point!.longitude,
        street: _address?.street,
        neighborhood: _address?.neighborhood,
        anonymous: _anonymous,
        photos: _photos,
      );
      await _startInstitutionalFollowingIfRequested(submission.occurrenceId);
      AppSession.instance.contentRevision.value++;
      if (!mounted) return;
      setState(() {
        _submission = submission;
        _targetOccurrence = null;
        _step = _Step.successNew;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _step = _Step.review);
      showUrbToast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitToExisting(Occurrence occurrence) async {
    setState(() {
      _submitting = true;
      _step = _Step.checking;
    });
    try {
      final submission = await _service.addReport(
        occurrenceId: occurrence.id,
        title: _titleController.text.trim().isEmpty
            ? null
            : _titleController.text.trim(),
        description: _descriptionController.text,
        anonymous: _anonymous,
        photos: _photos,
      );
      await _startInstitutionalFollowingIfRequested(submission.occurrenceId);
      if (!mounted) return;
      final updated = await _service.fetchById(occurrence.id);
      if (updated != null) AppSession.instance.publish(updated);
      if (!mounted) return;
      setState(() {
        _submission = submission;
        _targetOccurrence = occurrence;
        _step = _Step.successAdded;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _step = _addingToExisting ? _Step.review : _Step.similar);
      showUrbToast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _startInstitutionalFollowingIfRequested(int occurrenceId) async {
    _councilorFollowingStarted = false;
    _councilorFollowingWarning = null;
    if (!_followAsCouncilor || !_canOfferCouncilorFollowing) return;
    try {
      await InstitutionalService().startCouncilorFollowing(occurrenceId);
      _councilorFollowingStarted = true;
    } catch (error) {
      _councilorFollowingWarning = friendlyError(error);
    }
  }

  void _viewOccurrence() {
    final submission = _submission;
    if (submission == null) return;
    Navigator.of(context).pop(submission);
    openOccurrence(context, occurrenceId: submission.occurrenceId);
  }

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------

  int get _stepIndex => switch (_step) {
    _Step.category => 0,
    _Step.evidence => 1,
    _ => 2,
  };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: UrbColors.canvas,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: KeyedSubtree(key: ValueKey(_step), child: _body()),
          ),
        ),
      ),
    );
  }

  Widget _body() => switch (_step) {
    _Step.category => _scaffoldStep(_categoryStep()),
    _Step.evidence => _scaffoldStep(_evidenceStep()),
    _Step.review => _scaffoldStep(_reviewStep()),
    _Step.checking => _checking(),
    _Step.similar => _similarStep(),
    _Step.successNew => _success(created: true),
    _Step.successAdded => _success(created: false),
  };

  Widget _header({bool showTrack = true}) {
    final steps = _addingToExisting ? 2 : 3;
    final index = _addingToExisting ? (_stepIndex - 1).clamp(0, 1) : _stepIndex;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          UrbSquareButton(
            icon: UrbIcons.chevronLeft,
            tooltip: 'Voltar',
            onPressed: _back,
          ),
          if (showTrack)
            Semantics(
              label: 'Passo ${index + 1} de $steps',
              child: Row(
                children: [
                  for (var i = 0; i < steps; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.only(left: 5),
                      width: 22,
                      height: 3,
                      decoration: BoxDecoration(
                        color: i <= index ? UrbColors.blue : UrbColors.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _scaffoldStep(Widget content) {
    return Column(
      children: [
        _header(),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
                child: content,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepEyebrow(int number) {
    final total = _addingToExisting ? 2 : 3;
    final shown = _addingToExisting ? number - 1 : number;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        'PASSO $shown DE $total',
        style: UrbText.eyebrow.copyWith(fontSize: 10.5, letterSpacing: 1.5),
      ),
    );
  }

  Widget _categoryStep() {
    final canContinue = _category != null && _city != null && _point != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepEyebrow(1),
        Text(
          'O que você\nencontrou?',
          style: UrbText.h1.copyWith(fontSize: 32),
        ),
        const SizedBox(height: 22),
        if (_categories.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: UrbLoadingView())
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in _categories)
                    SizedBox(
                      width: width,
                      child: _CategoryChip(
                        category: category,
                        selected: _category?.id == category.id,
                        onTap: () => setState(() => _category = category),
                      ),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(UrbRadius.md),
            border: Border.all(
              color: _locationError != null
                  ? UrbColors.warning
                  : UrbColors.line,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LOCAL DETECTADO',
                      style: UrbText.eyebrow.copyWith(
                        color: UrbColors.muted,
                        fontSize: 10,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const UrbIcon(
                          UrbIcons.location,
                          size: 13,
                          color: UrbColors.navy,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _locating
                                ? 'Identificando sua localização…'
                                : (_point == null
                                      ? 'Local não definido'
                                      : _address?.label ?? 'Local aproximado'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: UrbText.label.copyWith(
                              color: UrbColors.navy,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_locationError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _locationError!,
                        style: UrbText.caption.copyWith(
                          color: UrbColors.warning,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              UrbChip(
                label: 'Ajustar',
                icon: UrbIcons.map,
                selected: true,
                onTap: _adjustLocation,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        UrbPrimaryButton(
          label: 'Continuar',
          onPressed: canContinue
              ? () => setState(() => _step = _Step.evidence)
              : null,
        ),
      ],
    );
  }

  Widget _evidenceStep() {
    final existing = widget.existingOccurrence;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepEyebrow(2),
        Text(
          existing == null ? 'Mostre o que\nvocê viu' : 'Adicione seu\nrelato',
          style: UrbText.h1.copyWith(fontSize: 32),
        ),
        if (existing != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: UrbColors.line),
            ),
            child: Row(
              children: [
                OccurrenceImage(
                  url: existing.primaryImageUrl,
                  categoryName: existing.categoryName,
                  categorySlug: existing.categorySlug,
                  width: 52,
                  height: 52,
                  radius: 8,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        existing.categoryName.toUpperCase(),
                        style: UrbText.eyebrow.copyWith(fontSize: 10),
                      ),
                      Text(
                        existing.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: UrbText.titleSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var index = 0; index < _photos.length; index++)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _PhotoThumb(
                    file: _photos[index],
                    onRemove: () => setState(() => _photos.removeAt(index)),
                    index: index,
                  ),
                ),
              if (_photos.length < _maxPhotos)
                _AddPhotoTile(
                  label: _photos.isEmpty ? 'Adicionar foto' : 'Mais',
                  onTap: _addPhoto,
                ),
            ],
          ),
        ),
        if (_photos.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            existing == null
                ? 'Adicione pelo menos uma foto do problema. Ela ajuda a comunidade a confirmar que ele existe.'
                : 'Uma nova foto ajuda, mas é opcional.',
            style: UrbText.bodySmall.copyWith(
              color: existing == null
                  ? UrbColors.warning
                  : const Color(0xFF8FA0B0),
              fontSize: 12.5,
              fontWeight: existing == null ? FontWeight.w700 : null,
            ),
          ),
        ],
        const SizedBox(height: 20),
        UrbTextField(
          label: 'Descreva o problema',
          controller: _descriptionController,
          hint: 'Conte o que você observou e por que isso precisa de atenção.',
          maxLines: 5,
          minLines: 4,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          onChanged: _onDescriptionChanged,
        ),
        if (existing == null) ...[
          const SizedBox(height: 16),
          UrbTextField(
            label: 'Título',
            controller: _titleController,
            hint: 'Ex.: Semáforo intermitente no cruzamento',
            maxLength: 90,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (value) =>
                setState(() => _titleEdited = value.trim().isNotEmpty),
          ),
          const SizedBox(height: 2),
          Text(
            'Sugerido a partir da sua descrição. Você pode editar.',
            style: UrbText.caption.copyWith(fontSize: 12),
          ),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: UrbColors.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Publicar anonimamente',
                      style: UrbText.titleSmall.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Seu nome não será exibido publicamente neste relato. O UrbApp mantém o vínculo apenas para segurança e moderação.',
                      style: UrbText.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              UrbSwitch(
                value: _anonymous,
                label: 'Publicar anonimamente',
                onChanged: (value) => setState(() {
                  _anonymous = value;
                  if (value) _followAsCouncilor = false;
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        UrbPrimaryButton(
          label: 'Revisar relato',
          onPressed: _canReview
              ? () => setState(() => _step = _Step.review)
              : null,
        ),
      ],
    );
  }

  Widget _reviewRow(
    String label,
    Widget value,
    VoidCallback onEdit, {
    bool last = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: UrbColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: UrbText.eyebrow.copyWith(
              color: UrbColors.muted,
              fontSize: 10,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: value),
              const SizedBox(width: 10),
              UrbTextButton('Editar', onPressed: onEdit),
            ],
          ),
        ],
      ),
    );
  }

  Widget _reviewStep() {
    final valueStyle = UrbText.bodySmall.copyWith(
      color: UrbColors.navy,
      fontWeight: FontWeight.w600,
    );
    final existing = widget.existingOccurrence;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepEyebrow(3),
        Text('Tudo certo?', style: UrbText.h1.copyWith(fontSize: 32)),
        const SizedBox(height: 6),
        Text('Confira antes de enviar.', style: UrbText.body),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: UrbColors.line),
          ),
          child: Column(
            children: [
              if (existing == null) ...[
                _reviewRow(
                  'Categoria',
                  Text(_category?.name ?? '—', style: valueStyle),
                  () => setState(() => _step = _Step.category),
                ),
                _reviewRow(
                  'Local',
                  Text(
                    _address?.label ?? 'Local aproximado',
                    style: valueStyle,
                  ),
                  _adjustLocation,
                ),
              ] else
                _reviewRow(
                  'Ocorrência',
                  Text(existing.title, style: valueStyle),
                  () => Navigator.of(context).pop(),
                ),
              _reviewRow(
                'Título',
                Text(_generatedTitle(), style: valueStyle),
                () => setState(() => _step = _Step.evidence),
              ),
              _reviewRow(
                'Descrição',
                Text(
                  _descriptionController.text.trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: valueStyle,
                ),
                () => setState(() => _step = _Step.evidence),
              ),
              if (_photos.isNotEmpty)
                _reviewRow(
                  'Fotos',
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final photo in _photos)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: _XFileImage(file: photo, size: 38),
                        ),
                    ],
                  ),
                  () => setState(() => _step = _Step.evidence),
                ),
              _reviewRow(
                'Publicação',
                Text(
                  _anonymous ? 'Anônima' : 'Com seu nome',
                  style: valueStyle,
                ),
                () => setState(() => _step = _Step.evidence),
                last: true,
              ),
            ],
          ),
        ),
        if (_canOfferCouncilorFollowing) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFFF2EFFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD8D0F4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: UrbColors.violet,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const UrbIcon(
                    UrbIcons.building,
                    size: 17,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Acompanhar como vereador',
                        style: UrbText.titleSmall.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Inicia um acompanhamento institucional público após o envio. O relato continua sendo uma contribuição cidadã.',
                        style: UrbText.caption.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                UrbSwitch(
                  value: _followAsCouncilor,
                  label: 'Acompanhar institucionalmente',
                  onChanged: (value) =>
                      setState(() => _followAsCouncilor = value),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        UrbPrimaryButton(
          label: 'Enviar relato',
          loading: _submitting,
          onPressed: _submitting ? null : _submitForCheck,
        ),
        const SizedBox(height: 12),
        Text(
          'Você poderá acompanhar seu relato após o envio.',
          textAlign: TextAlign.center,
          style: UrbText.caption,
        ),
      ],
    );
  }

  Widget _checking() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const UrbPulsingDots(),
            const SizedBox(height: 28),
            Text(
              _submitting
                  ? 'Enviando seu relato…'
                  : 'Verificando ocorrências próximas…',
              textAlign: TextAlign.center,
              style: UrbText.h3.copyWith(fontSize: 21),
            ),
            const SizedBox(height: 10),
            Text(
              _submitting
                  ? 'Estamos registrando suas informações e evidências.'
                  : 'Verificamos se este problema já foi registrado por outros cidadãos antes de criar uma nova ocorrência.',
              textAlign: TextAlign.center,
              style: UrbText.body,
            ),
          ],
        ),
      ),
    );
  }

  Widget _similarStep() {
    final main = _candidates.first;
    final others = _candidates.skip(1).take(2).toList();
    return Column(
      children: [
        _header(showTrack: false),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'POSSÍVEL DUPLICATA',
                      style: UrbText.eyebrow.copyWith(
                        color: const Color(0xFFC2610A),
                        fontSize: 10.5,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Encontramos uma ocorrência parecida por perto',
                  style: UrbText.h2.copyWith(color: UrbColors.navy),
                ),
                const SizedBox(height: 6),
                Text(
                  'Pode ser o mesmo problema que você está relatando.',
                  style: UrbText.body,
                ),
                const SizedBox(height: 20),
                _SimilarCard(
                  candidate: main,
                  onTap: () => openOccurrence(
                    context,
                    occurrenceId: main.occurrence.id,
                    initial: main.occurrence,
                  ),
                ),
                const SizedBox(height: 22),
                Text('É o mesmo problema?', style: UrbText.title),
                const SizedBox(height: 14),
                _ChoiceButton(
                  primary: true,
                  title: 'Sim, é o mesmo',
                  subtitle: 'Adicionar meu relato a esta ocorrência',
                  onTap: _submitting
                      ? null
                      : () => _submitToExisting(main.occurrence),
                ),
                const SizedBox(height: 10),
                _ChoiceButton(
                  title: 'É outro problema',
                  subtitle: 'Criar uma nova ocorrência',
                  onTap: _submitting ? null : _createNew,
                ),
                if (others.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  const UrbEyebrow('Outras ocorrências próximas', muted: true),
                  const SizedBox(height: 6),
                  for (final candidate in others)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _SimilarCard(
                        candidate: candidate,
                        compact: true,
                        onTap: () => _submitToExisting(candidate.occurrence),
                        actionLabel: 'Adicionar relato aqui',
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _success({required bool created}) {
    final submission = _submission;
    final reports = submission?.reportsCount ?? 1;
    final firstContribution =
        created || !(_targetOccurrence?.contributedByMe ?? false);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 40, 28, 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: created
                      ? const Color(0xFFEEF0FF)
                      : UrbColors.successSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: UrbIcon(
                  UrbIcons.checkCircle,
                  size: 34,
                  color: created ? UrbColors.blue : UrbColors.success,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                created ? 'Problema registrado' : 'Relato adicionado',
                style: UrbText.h1,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text.rich(
                created
                    ? const TextSpan(
                        text:
                            'Seu relato iniciou uma nova ocorrência na cidade. A comunidade já pode acompanhar e apoiar.',
                      )
                    : TextSpan(
                        children: [
                          const TextSpan(text: 'Agora '),
                          TextSpan(
                            text:
                                '$reports ${reports == 1 ? 'relato' : 'relatos'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: UrbColors.navy,
                            ),
                          ),
                          const TextSpan(
                            text:
                                ' descrevem este problema. Sua contribuição ajuda a dar mais visibilidade a esta ocorrência.',
                          ),
                        ],
                      ),
                textAlign: TextAlign.center,
                style: UrbText.body.copyWith(fontSize: 15),
              ),
              const SizedBox(height: 20),
              if (firstContribution)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8EE),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFD8E8A0)),
                  ),
                  child: Text(
                    '+$pointsPerPost pontos de participação',
                    style: UrbText.caption.copyWith(
                      color: UrbColors.limeText,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (_councilorFollowingStarted) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2EFFF),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    children: [
                      const UrbIcon(
                        UrbIcons.check,
                        size: 16,
                        color: UrbColors.violet,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Acompanhamento institucional iniciado. Agora registre sua primeira atuação.',
                          style: UrbText.caption.copyWith(
                            color: const Color(0xFF493A89),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (_councilorFollowingWarning != null) ...[
                const SizedBox(height: 12),
                Text(
                  'O relato foi enviado, mas o acompanhamento não pôde ser iniciado: $_councilorFollowingWarning',
                  textAlign: TextAlign.center,
                  style: UrbText.caption.copyWith(color: UrbColors.orange),
                ),
              ],
              const SizedBox(height: 28),
              UrbPrimaryButton(
                label: _councilorFollowingStarted
                    ? 'Registrar primeira atuação'
                    : 'Ver ocorrência',
                onPressed: _viewOccurrence,
              ),
              const SizedBox(height: 8),
              UrbTextButton(
                'Voltar ao início',
                color: UrbColors.muted,
                onPressed: () => Navigator.of(context).pop(submission),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final CategoryOption category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? UrbColors.blueSoft : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? UrbColors.blue : UrbColors.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: categoryColor(category.slug, category.name),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    category.name,
                    style: UrbText.label.copyWith(
                      color: selected ? UrbColors.blue : UrbColors.navy,
                      height: 1.3,
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

class _XFileImage extends StatelessWidget {
  const _XFileImage({required this.file, required this.size});

  final XFile file;
  final double size;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snapshot) => snapshot.hasData
          ? Image.memory(
              snapshot.data!,
              width: size,
              height: size,
              fit: BoxFit.cover,
            )
          : Container(width: size, height: size, color: UrbColors.canvasAlt),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({
    required this.file,
    required this.onRemove,
    required this.index,
  });

  final XFile file;
  final VoidCallback onRemove;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: UrbColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: _XFileImage(file: file, size: 84),
        ),
        Positioned(
          top: 5,
          right: 5,
          child: Semantics(
            button: true,
            label: 'Remover foto ${index + 1}',
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Color(0x8C000000),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const UrbIcon(
                  UrbIcons.close,
                  size: 12,
                  color: Colors.white,
                  strokeWidth: 2.2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: CustomPaint(
          painter: _DashedBorderPainter(),
          child: SizedBox(
            width: 84,
            height: 84,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const UrbIcon(
                  UrbIcons.camera,
                  size: 21,
                  color: Color(0xFF8492A4),
                ),
                const SizedBox(height: 5),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    label.toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: UrbText.caption.copyWith(
                      color: const Color(0xFF8492A4),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      height: 1.2,
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

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC6CDD5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(11)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
        distance += 9;
      }
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(11)),
      Paint()..color = Colors.white.withValues(alpha: 0.0),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SimilarCard extends StatelessWidget {
  const _SimilarCard({
    required this.candidate,
    required this.onTap,
    this.compact = false,
    this.actionLabel,
  });

  final DuplicateCandidate candidate;
  final VoidCallback onTap;
  final bool compact;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final occurrence = candidate.occurrence;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: UrbColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: compact ? 70 : 88,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    OccurrenceImage(
                      url: occurrence.primaryImageUrl,
                      categoryName: occurrence.categoryName,
                      categorySlug: occurrence.categorySlug,
                      radius: 0,
                      height: compact ? 80 : 116,
                    ),
                    if (!compact)
                      Positioned(
                        left: 6,
                        right: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x85000000),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            occurrence.categoryName,
                            maxLines: 2,
                            style: UrbText.caption.copyWith(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        occurrence.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: UrbText.titleSmall.copyWith(
                          fontWeight: FontWeight.w800,
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
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${occurrence.locationLabel} · ',
                                  ),
                                  TextSpan(
                                    text: formatDistance(candidate.distanceKm),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: UrbColors.navy,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: UrbText.caption.copyWith(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusPill(occurrence.status, compact: true),
                          Text(
                            '${plural(occurrence.reportsCount, 'relato', 'relatos')} · ${plural(occurrence.supportsCount, 'apoio', 'apoios')}',
                            style: UrbText.caption,
                          ),
                        ],
                      ),
                      if (actionLabel != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          actionLabel!,
                          style: UrbText.caption.copyWith(
                            color: UrbColors.blue,
                            fontWeight: FontWeight.w800,
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
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? UrbColors.blueSoft : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(
          color: primary
              ? UrbColors.blue.withValues(alpha: 0.28)
              : UrbColors.line,
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: UrbText.title.copyWith(
                  fontSize: 15,
                  color: primary ? UrbColors.blue : UrbColors.navy,
                ),
              ),
              const SizedBox(height: 3),
              Text(subtitle, style: UrbText.bodySmall.copyWith(fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}
