import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../domain/occurrence_status.dart';
import '../../theme/app_theme.dart';
import 'urb_components.dart';

enum CouncilorOccurrenceScope { mine, unattended }

class OccurrenceFilters {
  const OccurrenceFilters({
    this.categoryId,
    this.status,
    this.maxDistanceKm,
    this.neighborhood = '',
    this.councilorScope,
  });

  final int? categoryId;
  final OccurrenceStatus? status;
  final double? maxDistanceKm;
  final String neighborhood;
  final CouncilorOccurrenceScope? councilorScope;

  int get activeCount =>
      [categoryId != null, status != null, maxDistanceKm != null, neighborhood.trim().isNotEmpty, councilorScope != null]
          .where((v) => v)
          .length;

  static const empty = OccurrenceFilters();
}

/// "Refine a descoberta": categoria, status, distância e bairro.
Future<OccurrenceFilters?> showOccurrenceFilterSheet(
  BuildContext context, {
  required OccurrenceFilters current,
  required List<CategoryOption> categories,
  bool showCouncilorFilters = false,
}) {
  return showUrbSheet<OccurrenceFilters>(
    context: context,
    eyebrow: 'Refine a descoberta',
    title: 'Filtros',
    builder: (sheetContext) => _FilterBody(
      current: current,
      categories: categories,
      showCouncilorFilters: showCouncilorFilters,
    ),
  );
}

class _FilterBody extends StatefulWidget {
  const _FilterBody({required this.current, required this.categories, required this.showCouncilorFilters});

  final OccurrenceFilters current;
  final List<CategoryOption> categories;
  final bool showCouncilorFilters;

  @override
  State<_FilterBody> createState() => _FilterBodyState();
}

class _FilterBodyState extends State<_FilterBody> {
  late int? _category = widget.current.categoryId;
  late OccurrenceStatus? _status = widget.current.status;
  late double? _distance = widget.current.maxDistanceKm;
  late final _neighborhood = TextEditingController(text: widget.current.neighborhood);
  late CouncilorOccurrenceScope? _councilorScope = widget.current.councilorScope;

  @override
  void dispose() {
    _neighborhood.dispose();
    super.dispose();
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T?>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: UrbText.label.copyWith(color: const Color(0xFF34445A), fontWeight: FontWeight.w800)),
        const SizedBox(height: 7),
        DropdownButtonFormField<T?>(
          initialValue: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          style: UrbText.bodySmall.copyWith(color: UrbColors.navy, fontWeight: FontWeight.w600),
          decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dropdown<int>(
          label: 'Categoria',
          value: _category,
          items: [
            const DropdownMenuItem(value: null, child: Text('Todas')),
            for (final category in widget.categories)
              DropdownMenuItem(value: category.id, child: Text(category.name)),
          ],
          onChanged: (value) => setState(() => _category = value),
        ),
        const SizedBox(height: 13),
        _dropdown<OccurrenceStatus>(
          label: 'Status',
          value: _status,
          items: [
            const DropdownMenuItem(value: null, child: Text('Todos')),
            for (final status in OccurrenceStatus.values)
              DropdownMenuItem(value: status, child: Text(status.label)),
          ],
          onChanged: (value) => setState(() => _status = value),
        ),
        const SizedBox(height: 13),
        _dropdown<double>(
          label: 'Distância',
          value: _distance,
          items: const [
            DropdownMenuItem(value: null, child: Text('Qualquer distância')),
            DropdownMenuItem(value: 1, child: Text('Até 1 km')),
            DropdownMenuItem(value: 3, child: Text('Até 3 km')),
            DropdownMenuItem(value: 5, child: Text('Até 5 km')),
            DropdownMenuItem(value: 10, child: Text('Até 10 km')),
          ],
          onChanged: (value) => setState(() => _distance = value),
        ),
        const SizedBox(height: 13),
        UrbTextField(label: 'Bairro ou região', controller: _neighborhood, hint: 'Selecionar bairro'),
        if (widget.showCouncilorFilters) ...[
          const SizedBox(height: 13),
          _dropdown<CouncilorOccurrenceScope>(
            label: 'Acompanhamento parlamentar',
            value: _councilorScope,
            items: const [
              DropdownMenuItem(value: null, child: Text('Todas as ocorrências')),
              DropdownMenuItem(value: CouncilorOccurrenceScope.mine, child: Text('Acompanhadas por mim')),
              DropdownMenuItem(value: CouncilorOccurrenceScope.unattended, child: Text('Sem acompanhamento de vereador')),
            ],
            onChanged: (value) => setState(() => _councilorScope = value),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              flex: 5,
              child: UrbButton(
                label: 'Limpar filtros',
                tone: UrbButtonTone.soft,
                expand: true,
                onPressed: () => Navigator.of(context).pop(OccurrenceFilters.empty),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              flex: 6,
              child: UrbButton(
                label: 'Aplicar filtros',
                expand: true,
                onPressed: () => Navigator.of(context).pop(OccurrenceFilters(
                  categoryId: _category,
                  status: _status,
                  maxDistanceKm: _distance,
                  neighborhood: _neighborhood.text,
                  councilorScope: _councilorScope,
                )),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
