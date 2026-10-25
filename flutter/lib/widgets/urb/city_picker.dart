import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import 'urb_components.dart';
import 'urb_icon.dart';

const _brazilianStateNames = <String, String>{
  'AC': 'Acre',
  'AL': 'Alagoas',
  'AP': 'Amapá',
  'AM': 'Amazonas',
  'BA': 'Bahia',
  'CE': 'Ceará',
  'DF': 'Distrito Federal',
  'ES': 'Espírito Santo',
  'GO': 'Goiás',
  'MA': 'Maranhão',
  'MT': 'Mato Grosso',
  'MS': 'Mato Grosso do Sul',
  'MG': 'Minas Gerais',
  'PA': 'Pará',
  'PB': 'Paraíba',
  'PR': 'Paraná',
  'PE': 'Pernambuco',
  'PI': 'Piauí',
  'RJ': 'Rio de Janeiro',
  'RN': 'Rio Grande do Norte',
  'RS': 'Rio Grande do Sul',
  'RO': 'Rondônia',
  'RR': 'Roraima',
  'SC': 'Santa Catarina',
  'SP': 'São Paulo',
  'SE': 'Sergipe',
  'TO': 'Tocantins',
};

/// Seleção de cidade em três etapas: estado, inicial e cidade.
Future<CityOption?> showCityPicker(
  BuildContext context, {
  required List<CityOption> cities,
  CityOption? selected,
}) {
  return showUrbSheet<CityOption>(
    context: context,
    eyebrow: 'Sua cidade',
    title: 'Escolha a cidade',
    builder: (sheetContext) =>
        _CityPickerBody(cities: cities, selected: selected),
  );
}

class _CityPickerBody extends StatefulWidget {
  const _CityPickerBody({required this.cities, this.selected});

  final List<CityOption> cities;
  final CityOption? selected;

  @override
  State<_CityPickerBody> createState() => _CityPickerBodyState();
}

class _CityPickerBodyState extends State<_CityPickerBody> {
  _CityPickerStep _step = _CityPickerStep.state;
  String? _stateCode;
  String? _initial;

  String _stateName(String code) =>
      _brazilianStateNames[code.toUpperCase()] ?? code.toUpperCase();

  List<String> get _stateCodes {
    final codes = widget.cities
        .map((city) => city.stateCode.toUpperCase())
        .toSet()
        .toList();
    codes.sort(
      (a, b) => LocationService.normalize(
        _stateName(a),
      ).compareTo(LocationService.normalize(_stateName(b))),
    );
    return codes;
  }

  List<CityOption> get _stateCities {
    final code = _stateCode;
    if (code == null) return const [];
    final cities = widget.cities
        .where((city) => city.stateCode.toUpperCase() == code)
        .toList();
    cities.sort(
      (a, b) => LocationService.normalize(
        a.name,
      ).compareTo(LocationService.normalize(b.name)),
    );
    return cities;
  }

  String _cityInitial(CityOption city) {
    final normalized = LocationService.normalize(city.name).trim();
    return normalized.isEmpty ? '#' : normalized[0].toUpperCase();
  }

  List<String> get _initials {
    final initials =
        _stateCities
            .map(_cityInitial)
            .where((initial) => RegExp(r'^[A-Z]$').hasMatch(initial))
            .toSet()
            .toList()
          ..sort();
    return initials;
  }

  List<CityOption> get _visibleCities {
    final initial = _initial;
    if (initial == null) return const [];
    return _stateCities.where((city) => _cityInitial(city) == initial).toList();
  }

  void _selectState(String code) {
    setState(() {
      _stateCode = code;
      _initial = null;
      _step = _CityPickerStep.initial;
    });
  }

  void _selectInitial(String initial) {
    setState(() {
      _initial = initial;
      _step = _CityPickerStep.city;
    });
  }

  void _goBack() {
    setState(() {
      if (_step == _CityPickerStep.city) {
        _initial = null;
        _step = _CityPickerStep.initial;
      } else {
        _stateCode = null;
        _step = _CityPickerStep.state;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_step != _CityPickerStep.state) ...[
          _CityPickerBackRow(
            label: _step == _CityPickerStep.city
                ? '${_stateName(_stateCode!)} · $_initial'
                : _stateName(_stateCode!),
            onTap: _goBack,
          ),
          const SizedBox(height: 14),
        ],
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: switch (_step) {
            _CityPickerStep.state => _buildStates(),
            _CityPickerStep.initial => _buildInitials(),
            _CityPickerStep.city => _buildCities(),
          },
        ),
      ],
    );
  }

  Widget _buildStates() => Column(
    key: const ValueKey('states'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Selecione primeiro o estado.',
        style: UrbText.bodySmall.copyWith(color: UrbColors.muted),
      ),
      const SizedBox(height: 10),
      ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.5,
        ),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _stateCodes.length,
          itemBuilder: (context, index) {
            final code = _stateCodes[index];
            final selected = code == widget.selected?.stateCode.toUpperCase();
            return _CityPickerRow(
              label: _stateName(code),
              trailing: code,
              selected: selected,
              onTap: () => _selectState(code),
            );
          },
        ),
      ),
    ],
  );

  Widget _buildInitials() => Column(
    key: ValueKey('initials-$_stateCode'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Agora escolha a letra inicial da cidade.',
        style: UrbText.bodySmall.copyWith(color: UrbColors.muted),
      ),
      const SizedBox(height: 12),
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 5,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (final initial in _initials)
            _CityInitialButton(
              initial: initial,
              selected:
                  widget.selected != null &&
                  widget.selected!.stateCode.toUpperCase() == _stateCode &&
                  _cityInitial(widget.selected!) == initial,
              onTap: () => _selectInitial(initial),
            ),
        ],
      ),
    ],
  );

  Widget _buildCities() => Column(
    key: ValueKey('cities-$_stateCode-$_initial'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Escolha uma cidade com a inicial $_initial.',
        style: UrbText.bodySmall.copyWith(color: UrbColors.muted),
      ),
      const SizedBox(height: 10),
      ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.5,
        ),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _visibleCities.length,
          itemBuilder: (context, index) {
            final city = _visibleCities[index];
            return _CityPickerRow(
              label: city.name,
              trailing: city.stateCode.toUpperCase(),
              selected: city.id == widget.selected?.id,
              onTap: () => Navigator.of(context).pop(city),
            );
          },
        ),
      ),
    ],
  );
}

enum _CityPickerStep { state, initial, city }

class _CityPickerBackRow extends StatelessWidget {
  const _CityPickerBackRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Material(
      color: UrbColors.blueSoft,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const UrbIcon(
                UrbIcons.chevronLeft,
                size: 16,
                color: UrbColors.blue,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: UrbText.bodySmall.copyWith(
                  color: UrbColors.blue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CityPickerRow extends StatelessWidget {
  const _CityPickerRow({
    required this.label,
    required this.trailing,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String trailing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? UrbColors.blueSoft : Colors.transparent,
    borderRadius: BorderRadius.circular(9),
    child: InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: UrbText.bodySmall.copyWith(
                  color: selected ? UrbColors.blue : const Color(0xFF536174),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              trailing,
              style: UrbText.caption.copyWith(
                color: selected ? UrbColors.blue : UrbColors.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            UrbIcon(
              selected ? UrbIcons.check : UrbIcons.chevron,
              size: 16,
              color: selected ? UrbColors.blue : UrbColors.muted,
            ),
          ],
        ),
      ),
    ),
  );
}

class _CityInitialButton extends StatelessWidget {
  const _CityInitialButton({
    required this.initial,
    required this.selected,
    required this.onTap,
  });

  final String initial;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? UrbColors.blue : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(11),
      side: BorderSide(
        color: selected ? UrbColors.blue : const Color(0xFFD7DDE4),
      ),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: Center(
        child: Text(
          initial,
          style: UrbText.titleSmall.copyWith(
            color: selected ? Colors.white : UrbColors.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ),
  );
}

/// Seletor "Sua cidade" do cabeçalho da Home.
class CitySelectorButton extends StatelessWidget {
  const CitySelectorButton({
    super.key,
    required this.city,
    required this.onTap,
    this.label = 'Sua cidade',
  });

  final CityOption? city;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label: ${city?.name ?? 'não selecionada'}',
      excludeSemantics: true,
      child: Material(
        color: Colors.white.withValues(alpha: 0.86),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UrbRadius.md),
          side: const BorderSide(color: Color(0xFFD7DDE4)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(UrbRadius.md),
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  const UrbIcon(
                    UrbIcons.location,
                    size: 19,
                    color: UrbColors.blue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label.toUpperCase(),
                          style: UrbText.eyebrow.copyWith(
                            color: const Color(0xFF8B96A5),
                            fontSize: 9.5,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          city?.name ?? 'Selecionar cidade',
                          style: UrbText.titleSmall.copyWith(
                            color: const Color(0xFF13233B),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const UrbIcon(
                    UrbIcons.chevronDown,
                    size: 16,
                    color: Color(0xFF8B96A5),
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
