import 'package:flutter/material.dart';

import '../services/city_service.dart';
import '../theme/app_theme.dart';

class CityPickerResult {
  const CityPickerResult(this.cityId);

  final int? cityId;
}

Future<CityPickerResult?> showCityPickerSheet(
  BuildContext context, {
  required List<CityOption> cities,
  int? selectedCityId,
  bool allowAllCities = false,
}) {
  return showModalBottomSheet<CityPickerResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _CityPickerSheet(
      cities: cities,
      selectedCityId: selectedCityId,
      allowAllCities: allowAllCities,
    ),
  );
}

class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet({
    required this.cities,
    required this.selectedCityId,
    required this.allowAllCities,
  });

  final List<CityOption> cities;
  final int? selectedCityId;
  final bool allowAllCities;

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  String? _stateCode;

  List<String> get _stateCodes {
    final codes = widget.cities.map((city) => city.stateCode).toSet().toList();
    codes.sort(
      (first, second) => (brazilianStateNames[first] ?? first).compareTo(
        brazilianStateNames[second] ?? second,
      ),
    );
    return codes;
  }

  List<CityOption> get _stateCities {
    final stateCode = _stateCode;
    if (stateCode == null) return const [];
    final result = widget.cities
        .where((city) => city.stateCode == stateCode)
        .toList();
    result.sort((first, second) => first.name.compareTo(second.name));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final stateCode = _stateCode;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  if (stateCode != null)
                    IconButton(
                      tooltip: 'Voltar para os estados',
                      onPressed: () => setState(() => _stateCode = null),
                      icon: const Icon(Icons.arrow_back_rounded),
                    )
                  else
                    const SizedBox(width: 48),
                  Expanded(
                    child: Text(
                      stateCode == null
                          ? 'Selecione o estado'
                          : 'Selecione a cidade',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                shrinkWrap: true,
                children: stateCode == null
                    ? _buildStateOptions(context)
                    : _buildCityOptions(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStateOptions(BuildContext context) {
    return [
      if (widget.allowAllCities)
        _PickerTile(
          icon: Icons.public_rounded,
          title: 'Todas as cidades',
          selected: widget.selectedCityId == null,
          onTap: () => Navigator.of(context).pop(const CityPickerResult(null)),
        ),
      ..._stateCodes.map(
        (stateCode) => _PickerTile(
          icon: Icons.map_outlined,
          title: brazilianStateNames[stateCode] ?? stateCode.toUpperCase(),
          trailing: stateCode.toUpperCase(),
          onTap: () => setState(() => _stateCode = stateCode),
        ),
      ),
    ];
  }

  List<Widget> _buildCityOptions(BuildContext context) {
    return _stateCities
        .map(
          (city) => _PickerTile(
            icon: Icons.location_city_outlined,
            title: city.name,
            selected: city.id == widget.selectedCityId,
            onTap: () => Navigator.of(context).pop(CityPickerResult(city.id)),
          ),
        )
        .toList();
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailing,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? trailing;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Icon(
        selected ? Icons.check_circle_rounded : icon,
        color: selected ? AppColors.primary : AppColors.textSecondary,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      trailing: trailing == null
          ? null
          : Text(
              trailing!,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}
