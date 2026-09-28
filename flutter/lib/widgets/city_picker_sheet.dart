import 'package:flutter/material.dart';

import '../services/city_service.dart';
import '../theme/urbapp_design.dart';
import 'urb_dialog.dart';

class CityPickerResult {
  const CityPickerResult(this.cityId);

  final int? cityId;
}

/// Abre a escolha de cidade como janela flutuante no meio da tela
/// (primeiro o estado, depois a cidade).
///
/// O nome continua "Sheet" para não precisar mudar as telas que já usam.
Future<CityPickerResult?> showCityPickerSheet(
  BuildContext context, {
  required List<CityOption> cities,
  int? selectedCityId,
  bool allowAllCities = false,
}) {
  return showUrbDialog<CityPickerResult>(
    context: context,
    builder: (_) => _CityPickerDialog(
      cities: cities,
      selectedCityId: selectedCityId,
      allowAllCities: allowAllCities,
    ),
  );
}

class _CityPickerDialog extends StatefulWidget {
  const _CityPickerDialog({
    required this.cities,
    required this.selectedCityId,
    required this.allowAllCities,
  });

  final List<CityOption> cities;
  final int? selectedCityId;
  final bool allowAllCities;

  @override
  State<_CityPickerDialog> createState() => _CityPickerDialogState();
}

class _CityPickerDialogState extends State<_CityPickerDialog> {
  final _searchController = TextEditingController();
  String? _stateCode;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    // Se já existe uma cidade escolhida, abre direto no estado dela.
    final selected = widget.cities
        .where((c) => c.id == widget.selectedCityId)
        .firstOrNull;
    _stateCode = selected?.stateCode;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static String _normalize(String value) {
    const map = {
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ã': 'a',
      'é': 'e',
      'ê': 'e',
      'í': 'i',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ú': 'u',
      'ü': 'u',
      'ç': 'c',
    };
    var result = value.trim().toLowerCase();
    map.forEach((from, to) => result = result.replaceAll(from, to));
    return result;
  }

  String _stateName(String code) =>
      brazilianStateNames[code] ?? code.toUpperCase();

  List<String> get _stateCodes {
    final codes = widget.cities.map((city) => city.stateCode).toSet().toList()
      ..sort((a, b) => _stateName(a).compareTo(_stateName(b)));
    final filter = _normalize(_filter);
    if (filter.isEmpty) return codes;
    return codes
        .where(
          (code) =>
              _normalize(_stateName(code)).contains(filter) ||
              code.toLowerCase() == filter,
        )
        .toList();
  }

  List<CityOption> get _stateCities {
    final stateCode = _stateCode;
    if (stateCode == null) return const [];
    final filter = _normalize(_filter);
    return widget.cities
        .where((city) => city.stateCode == stateCode)
        .where(
          (city) => filter.isEmpty || _normalize(city.name).contains(filter),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  void _goTo(String? stateCode) {
    _searchController.clear();
    setState(() {
      _stateCode = stateCode;
      _filter = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final stateCode = _stateCode;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.78;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              title: stateCode == null
                  ? 'Selecione o estado'
                  : _stateName(stateCode),
              subtitle: stateCode == null
                  ? 'Depois você escolhe a cidade.'
                  : 'Selecione a cidade',
              onBack: stateCode == null ? null : () => _goTo(null),
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _filter = value),
              textAlign: TextAlign.center,
              style: UrbText.body(size: 15, color: UrbColors.ink, height: 1.3),
              decoration: InputDecoration(
                hintText: stateCode == null ? 'Buscar estado' : 'Buscar cidade',
                hintStyle: UrbText.body(
                  size: 15,
                  color: UrbColors.textMuted,
                  height: 1.3,
                ),
                filled: true,
                fillColor: UrbColors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: UrbColors.textMuted,
                  size: 20,
                ),
                suffixIcon: const SizedBox(width: 48),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: UrbColors.border,
                    width: 1.5,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: UrbColors.border,
                    width: 1.5,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: UrbColors.violet,
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              // A lista desliza para o lado ao trocar de estado para cidade.
              child: AnimatedSwitcher(
                duration: UrbMotion.of(context, UrbMotion.fast),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0.06, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: ListView(
                  key: ValueKey(stateCode ?? 'estados'),
                  shrinkWrap: true,
                  children: stateCode == null
                      ? _stateOptions(context)
                      : _cityOptions(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _stateOptions(BuildContext context) {
    final codes = _stateCodes;
    return [
      if (widget.allowAllCities && _filter.isEmpty)
        _Option(
          icon: Icons.public_rounded,
          title: 'Todas as cidades',
          selected: widget.selectedCityId == null,
          onTap: () => Navigator.of(context).pop(const CityPickerResult(null)),
        ),
      for (final code in codes)
        _Option(
          icon: Icons.map_outlined,
          title: _stateName(code),
          trailing: code.toUpperCase(),
          selected: widget.cities.any(
            (c) => c.id == widget.selectedCityId && c.stateCode == code,
          ),
          showCheck: false,
          onTap: () => _goTo(code),
        ),
      if (codes.isEmpty) const _NothingFound(),
    ];
  }

  List<Widget> _cityOptions(BuildContext context) {
    final cities = _stateCities;
    return [
      for (final city in cities)
        _Option(
          icon: Icons.location_city_outlined,
          title: city.name,
          selected: city.id == widget.selectedCityId,
          onTap: () => Navigator.of(context).pop(CityPickerResult(city.id)),
        ),
      if (cities.isEmpty) const _NothingFound(),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    Widget square(IconData icon, String tooltip, VoidCallback onTap) => Tooltip(
      message: tooltip,
      child: Material(
        color: UrbColors.surface,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 19, color: const Color(0xFF374151)),
          ),
        ),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        onBack == null
            ? const SizedBox(width: 40)
            : square(
                Icons.arrow_back_rounded,
                'Voltar para os estados',
                onBack!,
              ),
        Expanded(
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: UrbColors.lavender,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Icon(
                  Icons.location_on_outlined,
                  color: UrbColors.violetDeep,
                  size: 24,
                ),
              ),
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: UrbMotion.of(context, UrbMotion.fast),
                child: Text(
                  title,
                  key: ValueKey(title),
                  textAlign: TextAlign.center,
                  style: UrbText.display(size: 22, weight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: UrbText.body(size: 14, height: 1.4),
              ),
            ],
          ),
        ),
        square(Icons.close_rounded, 'Fechar', onClose),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailing,
    this.selected = false,
    this.showCheck = true,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? trailing;
  final bool selected;
  final bool showCheck;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: selected ? UrbColors.lavender : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? UrbColors.violet.withValues(alpha: 0.45)
                    : UrbColors.border,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? UrbColors.violetDeep : UrbColors.textMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: UrbText.body(
                      size: 15,
                      weight: FontWeight.w700,
                      color: selected ? UrbColors.violetDeep : UrbColors.ink,
                      height: 1.2,
                    ),
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: UrbText.body(
                      size: 12,
                      weight: FontWeight.w700,
                      color: UrbColors.textMuted,
                      height: 1.2,
                    ),
                  ),
                if (trailing != null) const SizedBox(width: 6),
                if (showCheck && selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: UrbColors.violetDeep,
                    size: 20,
                  )
                else if (!showCheck)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: UrbColors.textMuted,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NothingFound extends StatelessWidget {
  const _NothingFound();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        'Nada encontrado. Tente outro nome.',
        textAlign: TextAlign.center,
        style: UrbText.body(size: 14, color: UrbColors.textMuted),
      ),
    );
  }
}
