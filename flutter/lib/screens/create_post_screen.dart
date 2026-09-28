import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../services/agency_service.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../theme/urbapp_design.dart';
import '../utils/error_formatter.dart';
import '../widgets/media_picker_widget.dart';
import '../widgets/urb_dialog.dart';
import '../widgets/urb_primary_button.dart';
import '../widgets/urb_text_field.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key, this.returnToPreviousOnSuccess = false});

  final bool returnToPreviousOnSuccess;

  /// Abre o "Novo reporte" como janela flutuante no meio da tela.
  static Future<bool?> open(BuildContext context) {
    final duration = UrbMotion.of(context, const Duration(milliseconds: 300));
    return Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        opaque: false,
        barrierColor: const Color(0x940D1520),
        barrierLabel: 'Fechar',
        transitionDuration: duration,
        reverseTransitionDuration: duration,
        pageBuilder: (_, _, _) =>
            const CreatePostScreen(returnToPreviousOnSuccess: true),
        transitionsBuilder: (context, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
          );
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween(begin: 0.9, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _formKey = GlobalKey<FormState>();

  /// Passo atual do assistente (0, 1 ou 2).
  int _step = 0;
  bool _published = false;
  String? _publishedNote;

  /// Busca de endereço digitado no passo do mapa.
  final _addressSearchController = TextEditingController();
  Timer? _addressSearchDebounce;
  List<_AddressResult> _addressResults = const [];
  bool _isSearchingAddress = false;
  bool _addressSearchDone = false;
  final _authService = AuthService();
  final _postService = PostService();
  final _mapController = MapController();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _categorySearchController = TextEditingController();

  List<LookupOption> _cities = const [];
  List<LookupOption> _categories = const [];
  List<AgencyOption> _agencies = const [];
  List<XFile> _images = [];

  LookupOption? _selectedCity;
  LookupOption? _selectedCategory;
  AgencyOption? _selectedAgency;

  LatLng? _selectedPoint;
  String _locationLabel = 'Buscando sua localizacao atual...';
  String _cityLabel = 'Cidade nao identificada';
  String? _resolvedStreet;
  String? _resolvedNeighborhood;
  String? _resolvedStateCode;
  bool _locationIsApproximate = false;

  bool _isAnonymous = false;
  bool _isSubmitting = false;
  bool _isLoadingLookups = true;
  bool _isLoadingLocation = true;
  bool _isResolvingAddress = false;

  Timer? _reverseGeocodeDebounce;

  static const LatLng _fallbackPoint = LatLng(-23.55052, -46.63331);

  @override
  void initState() {
    super.initState();
    _loadLookups();
  }

  @override
  void dispose() {
    _reverseGeocodeDebounce?.cancel();
    _addressSearchDebounce?.cancel();
    _addressSearchController.dispose();
    _mapController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _categorySearchController.dispose();
    super.dispose();
  }

  Future<void> _loadLookups() async {
    setState(() => _isLoadingLookups = true);

    try {
      final cities = await _postService.fetchCities();
      final categories = await _postService.fetchCategories();

      if (!mounted) return;

      setState(() {
        _cities = cities;
        _categories = categories;
        _isLoadingLookups = false;
      });

      await _initializeLocation();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoadingLookups = false;
        _isLoadingLocation = false;
      });
      _showError(friendlyError(error));
    }
  }

  Future<void> _initializeLocation() async {
    setState(() => _isLoadingLocation = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Ative a localizacao do dispositivo para usar o mapa.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Permissao de localizacao negada.');
      }

      final position = await Geolocator.getCurrentPosition();
      final point = LatLng(position.latitude, position.longitude);

      if (!mounted) return;

      setState(() {
        _selectedPoint = point;
        _isLoadingLocation = false;
      });

      _moveMap(point, 16);
      await _updateAddressFromPoint(point);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _selectedPoint = _fallbackPoint;
        _selectedCity = null;
        _selectedAgency = null;
        _agencies = const [];
        _isLoadingLocation = false;
        _locationLabel =
            'Nao foi possivel usar sua localizacao atual. Ajuste o pin manualmente no mapa.';
        _cityLabel = 'Cidade nao identificada';
        _resolvedStreet = null;
        _resolvedNeighborhood = null;
        _resolvedStateCode = null;
        _locationIsApproximate = true;
      });

      _moveMap(_fallbackPoint, 13);
      _showError(friendlyError(error));
    }
  }

  void _onAddressQueryChanged(String value) {
    _addressSearchDebounce?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _addressResults = const [];
        _isSearchingAddress = false;
        _addressSearchDone = false;
      });
      return;
    }
    setState(() => _isSearchingAddress = true);
    // Espera a pessoa parar de digitar (o serviço de mapas aceita
    // no máximo uma consulta por segundo).
    _addressSearchDebounce = Timer(
      const Duration(milliseconds: 700),
      () => _searchAddress(query),
    );
  }

  Future<void> _searchAddress(String query) async {
    final center = _selectedPoint ?? _fallbackPoint;
    try {
      // Dá preferência a endereços perto do ponto atual do mapa.
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'q': query,
        'limit': '5',
        'countrycodes': 'br',
        'accept-language': 'pt-BR',
        'viewbox':
            '${center.longitude - 0.4},${center.latitude + 0.4},'
            '${center.longitude + 0.4},${center.latitude - 0.4}',
        'bounded': '0',
      });

      final response = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Não foi possível buscar o endereço agora.');
      }

      final data = jsonDecode(response.body) as List<dynamic>;
      final results = data
          .map((item) => item as Map<String, dynamic>)
          .map((item) {
            final lat = double.tryParse('${item['lat']}');
            final lon = double.tryParse('${item['lon']}');
            if (lat == null || lon == null) return null;
            return _AddressResult(
              label: '${item['display_name'] ?? ''}',
              point: LatLng(lat, lon),
            );
          })
          .whereType<_AddressResult>()
          .toList();

      if (!mounted || _addressSearchController.text.trim() != query) return;
      setState(() {
        _addressResults = results;
        _isSearchingAddress = false;
        _addressSearchDone = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSearchingAddress = false;
        _addressSearchDone = true;
        _addressResults = const [];
      });
      _showError(friendlyError(error));
    }
  }

  void _selectAddress(_AddressResult result) {
    FocusScope.of(context).unfocus();
    _addressSearchDebounce?.cancel();
    final shortLabel = result.label.split(',').take(2).join(',').trim();
    _addressSearchController.text = shortLabel;
    setState(() {
      _selectedPoint = result.point;
      _addressResults = const [];
      _addressSearchDone = false;
    });
    _moveMap(result.point, 17);
    _updateAddressFromPoint(result.point);
  }

  void _moveMap(LatLng point, double zoom) {
    try {
      _mapController.move(point, zoom);
    } catch (_) {
      // O mapa ainda não apareceu; ele já abre no ponto escolhido.
    }
  }

  String? _validateRequired(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return 'Informe $label';
    }
    return null;
  }

  Future<void> _updateAddressFromPoint(LatLng point) async {
    if (!mounted) return;

    setState(() => _isResolvingAddress = true);

    try {
      final locationData = await _fetchAddressFromCoordinates(point);
      final street = locationData.street;
      final neighborhood = locationData.neighborhood;
      final locality = locationData.city;
      final stateCode = _stateCodeFromName(locationData.state);

      final locationParts = <String>[
        if (street.isNotEmpty) street,
        if (neighborhood.isNotEmpty) neighborhood,
      ];

      final matchedCity =
          _matchCity(locality, stateCode: stateCode) ??
          await _postService.findCityByName(
            cityName: locality,
            stateCode: stateCode,
          );

      if (!mounted) return;

      setState(() {
        _selectedPoint = point;
        _selectedCity = matchedCity;
        _selectedAgency = null;
        _cityLabel = locality.isNotEmpty ? locality : 'Cidade nao identificada';
        _resolvedStreet = street.isEmpty ? null : street;
        _resolvedNeighborhood = neighborhood.isEmpty ? null : neighborhood;
        _resolvedStateCode = stateCode;
        _locationIsApproximate =
            matchedCity == null || locality == 'Localizacao nao identificada';
        _locationLabel = locationParts.isEmpty
            ? 'Localizacao aproximada'
            : locationParts.join(' - ');
      });

      if (matchedCity != null) {
        await _loadAgenciesForCity(matchedCity.id);
      } else if (mounted) {
        setState(() => _agencies = const []);
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _selectedPoint = point;
        _selectedCity = null;
        _selectedAgency = null;
        _agencies = const [];
        _cityLabel = 'Cidade nao identificada';
        _locationLabel = 'Localizacao aproximada';
        _resolvedStreet = null;
        _resolvedNeighborhood = null;
        _resolvedStateCode = null;
        _locationIsApproximate = true;
      });
    } finally {
      if (mounted) {
        setState(() => _isResolvingAddress = false);
      }
    }
  }

  LookupOption? _matchCity(String? cityName, {String? stateCode}) {
    if (cityName == null || cityName.trim().isEmpty) return null;

    final normalizedTarget = _normalizeText(cityName);
    LookupOption? partialMatch;

    for (final city in _cities) {
      if (stateCode != null &&
          city.stateCode != null &&
          city.stateCode != stateCode) {
        continue;
      }

      final normalizedCityName = _normalizeText(city.name);
      if (normalizedCityName == normalizedTarget) {
        return city;
      }

      if (normalizedCityName.contains(normalizedTarget) ||
          normalizedTarget.contains(normalizedCityName)) {
        partialMatch ??= city;
      }
    }

    return partialMatch;
  }

  Future<({String street, String neighborhood, String city, String state})>
  _fetchAddressFromCoordinates(LatLng point) async {
    if (!kIsWeb) {
      try {
        final placemarks = await geo.placemarkFromCoordinates(
          point.latitude,
          point.longitude,
        );
        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          final street = _firstNonEmpty([
            placemark.street,
            placemark.thoroughfare,
            placemark.name,
          ]);
          final neighborhood = _firstNonEmpty([
            placemark.subLocality,
            placemark.locality,
            placemark.subAdministrativeArea,
          ]);
          final city = _firstNonEmpty([
            placemark.locality,
            placemark.subAdministrativeArea,
            placemark.administrativeArea,
            placemark.country,
          ]);

          return (
            street: street,
            neighborhood: neighborhood,
            city: city,
            state: placemark.administrativeArea ?? '',
          );
        }
      } catch (_) {}
    }

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
        'zoom': '18',
        'addressdetails': '1',
      });

      final response = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Falha ao consultar o endereco no mapa.');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final address = (data['address'] as Map<String, dynamic>?) ?? const {};

      final street =
          (address['road'] ?? address['pedestrian'] ?? address['footway'] ?? '')
              .toString()
              .trim();
      final neighborhood =
          (address['suburb'] ??
                  address['neighbourhood'] ??
                  address['quarter'] ??
                  '')
              .toString()
              .trim();
      final city =
          (address['city'] ??
                  address['town'] ??
                  address['village'] ??
                  address['municipality'] ??
                  address['county'] ??
                  address['state'] ??
                  address['country'] ??
                  'Localizacao nao identificada')
              .toString()
              .trim();
      final state = (address['state'] ?? address['region'] ?? '')
          .toString()
          .trim();

      return (
        street: street,
        neighborhood: neighborhood,
        city: city,
        state: state,
      );
    } catch (_) {
      return (
        street: '',
        neighborhood: '',
        city: 'Localizacao nao identificada',
        state: '',
      );
    }
  }

  String _normalizeText(String value) {
    const replacements = {
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'é': 'e',
      'ê': 'e',
      'í': 'i',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ú': 'u',
      'ç': 'c',
      'Ã¡': 'a',
      'Ã ': 'a',
      'Ã£': 'a',
      'Ã¢': 'a',
      'Ã©': 'e',
      'Ãª': 'e',
      'Ã­': 'i',
      'Ã³': 'o',
      'Ã´': 'o',
      'Ãµ': 'o',
      'Ãº': 'u',
      'Ã§': 'c',
    };

    var normalized = value.trim().toLowerCase();
    replacements.forEach((source, target) {
      normalized = normalized.replaceAll(source, target);
    });

    normalized = normalized
        .replaceAll(RegExp(r'^municipio de\s+'), '')
        .replaceAll(RegExp(r'^cidade de\s+'), '')
        .replaceAll(RegExp(r'^estancia turistica de\s+'), '')
        .replaceAll(RegExp(r'\s*[-/]\s*[a-z]{2}$'), '')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return normalized;
  }

  String? _stateCodeFromName(String? stateName) {
    if (stateName == null || stateName.trim().isEmpty) return null;

    const stateMap = {
      'acre': 'ac',
      'alagoas': 'al',
      'amapa': 'ap',
      'amazonas': 'am',
      'bahia': 'ba',
      'ceara': 'ce',
      'distrito federal': 'df',
      'espirito santo': 'es',
      'goias': 'go',
      'maranhao': 'ma',
      'mato grosso': 'mt',
      'mato grosso do sul': 'ms',
      'minas gerais': 'mg',
      'para': 'pa',
      'paraiba': 'pb',
      'parana': 'pr',
      'pernambuco': 'pe',
      'piaui': 'pi',
      'rio de janeiro': 'rj',
      'rio grande do norte': 'rn',
      'rio grande do sul': 'rs',
      'rondonia': 'ro',
      'roraima': 'rr',
      'santa catarina': 'sc',
      'sao paulo': 'sp',
      'sergipe': 'se',
      'tocantins': 'to',
    };

    final normalizedState = _normalizeText(stateName);
    return stateMap[normalizedState] ?? normalizedState;
  }

  Future<void> _loadAgenciesForCity(int cityId) async {
    try {
      final agencies = await _postService.fetchAgenciesByCity(cityId);
      if (!mounted) return;
      setState(() {
        _agencies = agencies;
        if (_selectedAgency != null && _selectedAgency!.cityId != cityId) {
          _selectedAgency = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _agencies = const [];
        _selectedAgency = null;
      });
    }
  }

  Future<LookupOption?> _resolveCityForSubmission() async {
    final localMatch =
        _selectedCity ?? _matchCity(_cityLabel, stateCode: _resolvedStateCode);
    if (localMatch != null) return localMatch;

    if (_cityLabel.trim().isEmpty ||
        _cityLabel == 'Localizacao nao identificada') {
      return null;
    }

    return _postService.findCityByName(
      cityName: _cityLabel,
      stateCode: _resolvedStateCode,
    );
  }

  Future<void> _submitPost() async {
    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      _showError(
        'Sua sessão expirou. Entre novamente para publicar o reporte.',
      );
      return;
    }

    if (_selectedPoint == null) {
      _showError('Aguarde o mapa carregar ou escolha um ponto no mapa.');
      return;
    }

    if (_selectedCategory == null) {
      _showError('Selecione uma categoria.');
      return;
    }

    final matchedCity = await _resolveCityForSubmission();

    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    int? createdPostId;
    try {
      createdPostId = await _postService.createPost(
        userId: currentUser.id,
        cityId: matchedCity?.id,
        categoryId: _selectedCategory!.id,
        title: _titleController.text,
        description: _descriptionController.text,
        latitude: _selectedPoint!.latitude,
        longitude: _selectedPoint!.longitude,
        street: _resolvedStreet,
        neighborhood: _resolvedNeighborhood,
        agencyId: _selectedAgency?.id,
        isAnonymous: _isAnonymous,
      );

      try {
        await _postService.createInitialStatusHistory(
          postId: createdPostId,
          userId: currentUser.id,
        );

        await _postService.uploadPostImages(
          userId: currentUser.id,
          postId: createdPostId,
          files: _images,
        );
      } catch (_) {
        await _postService.deletePost(createdPostId);
        rethrow;
      }

      if (!mounted) return;

      // Mostra a comemoração dentro da janela e depois fecha sozinha.
      setState(() {
        _isSubmitting = false;
        _published = true;
        _publishedNote = matchedCity == null
            ? 'Publicado com localização aproximada.'
            : null;
      });

      await Future<void>.delayed(const Duration(milliseconds: 1600));
      if (!mounted) return;

      if (widget.returnToPreviousOnSuccess && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      } else {
        _resetForm(matchedCity);
      }
    } catch (error) {
      _showError(friendlyError(error));
    } finally {
      if (mounted && _isSubmitting) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _resetForm(LookupOption? matchedCity) {
    _titleController.clear();
    _descriptionController.clear();
    _categorySearchController.clear();
    setState(() {
      _step = 0;
      _published = false;
      _publishedNote = null;
      _isAnonymous = false;
      _selectedCity = matchedCity;
      _selectedCategory = null;
      _selectedAgency = null;
      _images = [];
      _resolvedStateCode = null;
      _locationIsApproximate = false;
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    showUrbSnack(context, message, error: true);
  }

  // ──────────────────────────────────────────────────────────
  // Navegação entre os passos
  // ──────────────────────────────────────────────────────────

  static const _stepTitles = [
    'O que aconteceu?',
    'Onde fica?',
    'Últimos detalhes',
  ];
  static const _stepSubtitles = [
    'Mostre e descreva o problema.',
    'Marque o local do problema no mapa.',
    'Confira e publique seu reporte.',
  ];

  void _next() {
    if (_step == 0) {
      if (!_formKey.currentState!.validate()) return;
      FocusScope.of(context).unfocus();
    }
    if (_step == 1 && (_isLoadingLocation || _selectedPoint == null)) {
      _showError('Aguarde o mapa carregar ou escolha um ponto no mapa.');
      return;
    }
    setState(() => _step += 1);
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step -= 1);
  }

  void _close() {
    if (_isSubmitting) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _chooseCategory() async {
    final option = await showUrbDialog<LookupOption>(
      context: context,
      builder: (_) => _OptionPickerDialog<LookupOption>(
        icon: Icons.sell_outlined,
        title: 'Categoria',
        subtitle: 'Qual é o tipo do problema?',
        searchHint: 'Buscar categoria',
        options: _categories,
        labelOf: (option) => option.name,
        isSelected: (option) => option.id == _selectedCategory?.id,
      ),
    );
    if (option == null || !mounted) return;
    setState(() {
      _selectedCategory = option;
      _categorySearchController.text = option.name;
    });
  }

  Future<void> _chooseAgency() async {
    const none = AgencyOption(
      id: -1,
      cityId: -1,
      name: 'Nenhum órgão vinculado',
      type: '',
      contactEmail: '',
    );
    final option = await showUrbDialog<AgencyOption>(
      context: context,
      builder: (_) => _OptionPickerDialog<AgencyOption>(
        icon: Icons.account_balance_outlined,
        title: 'Órgão responsável',
        subtitle: 'Opcional: ajuda a prefeitura a assumir o reporte.',
        searchHint: 'Buscar órgão',
        options: [none, ..._agencies],
        labelOf: (agency) =>
            agency.id == -1 ? agency.name : '${agency.name} (${agency.type})',
        isSelected: (agency) => agency.id == -1
            ? _selectedAgency == null
            : agency.id == _selectedAgency?.id,
      ),
    );
    if (option == null || !mounted) return;
    setState(() => _selectedAgency = option.id == -1 ? null : option);
  }

  // ──────────────────────────────────────────────────────────
  // Tela
  // ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSubmitting,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  clipBehavior: Clip.antiAlias,
                  child: AnimatedSize(
                    duration: UrbMotion.of(context, UrbMotion.medium),
                    curve: Curves.easeOutCubic,
                    child: _published ? _buildPublished() : _buildWizard(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWizard() {
    final isLast = _step == 2;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Barrinha de progresso: cada parte "enche" ao avançar.
              Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Stack(
                          children: [
                            Container(height: 6, color: UrbColors.border),
                            AnimatedFractionallySizedBox(
                              duration: UrbMotion.of(context, UrbMotion.medium),
                              curve: Curves.easeOutCubic,
                              widthFactor: i <= _step ? 1 : 0,
                              child: Container(
                                height: 6,
                                decoration: const BoxDecoration(
                                  gradient: UrbGradients.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 44),
                    child: AnimatedSwitcher(
                      duration: UrbMotion.of(context, UrbMotion.fast),
                      child: Column(
                        key: ValueKey(_step),
                        children: [
                          Text(
                            'PASSO ${_step + 1} DE 3',
                            style: UrbText.body(
                              size: 12,
                              weight: FontWeight.w700,
                              color: UrbColors.violet,
                              height: 1.3,
                            ).copyWith(letterSpacing: 1.2),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _stepTitles[_step],
                            textAlign: TextAlign.center,
                            style: UrbText.display(
                              size: 22,
                              weight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _stepSubtitles[_step],
                            textAlign: TextAlign.center,
                            style: UrbText.body(size: 14, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Material(
                      color: UrbColors.surface,
                      borderRadius: BorderRadius.circular(13),
                      child: InkWell(
                        onTap: _isSubmitting ? null : _close,
                        borderRadius: BorderRadius.circular(13),
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            // Os três passos ficam montados (o mapa precisa existir),
            // mas só o atual aparece.
            child: IndexedStack(
              index: _step,
              sizing: StackFit.loose,
              children: [
                _StepPane(active: _step == 0, child: _buildStepContent()),
                _StepPane(active: _step == 1, child: _buildStepLocation()),
                _StepPane(active: _step == 2, child: _buildStepDetails()),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Row(
            children: [
              AnimatedSize(
                duration: UrbMotion.of(context, UrbMotion.fast),
                child: _step == 0
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 120,
                          child: UrbSecondaryButton(
                            label: 'Voltar',
                            onPressed: _isSubmitting ? null : _back,
                          ),
                        ),
                      ),
              ),
              Expanded(
                child: UrbPrimaryButton(
                  label: isLast ? 'Publicar' : 'Continuar',
                  icon: isLast
                      ? Icons.send_rounded
                      : Icons.arrow_forward_rounded,
                  loading: _isSubmitting,
                  onPressed: isLast
                      ? ((_isLoadingLookups || _isLoadingLocation)
                            ? null
                            : _submitPost)
                      : _next,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Passo 1: fotos, título e descrição.
  Widget _buildStepContent() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Fotos',
            style: UrbText.body(
              size: 13,
              weight: FontWeight.w700,
              color: const Color(0xFF374151),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          MediaPickerWidget(
            images: _images,
            onChanged: (images) => setState(() => _images = images),
          ),
          const SizedBox(height: 20),
          UrbTextField(
            label: 'Título',
            controller: _titleController,
            icon: Icons.title_rounded,
            hintText: 'Ex.: Poste apagado na esquina',
            validator: (value) => _validateRequired(value, 'o título'),
          ),
          const SizedBox(height: 20),
          Text(
            'Descrição',
            style: UrbText.body(
              size: 13,
              weight: FontWeight.w700,
              color: const Color(0xFF374151),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _descriptionController,
            validator: (value) => _validateRequired(value, 'a descrição'),
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            minLines: 4,
            maxLines: 6,
            style: UrbText.body(size: 15, color: UrbColors.ink, height: 1.4),
            decoration: urbInputDecoration(hintText: 'Detalhe o seu problema')
                .copyWith(
                  prefixIcon: null,
                  suffixIcon: null,
                  contentPadding: const EdgeInsets.all(16),
                ),
          ),
        ],
      ),
    );
  }

  // Passo 2: mapa com o pino fixo no centro.
  Widget _buildStepLocation() {
    final cityText =
        _locationIsApproximate && _cityLabel != 'Localizacao nao identificada'
        ? '$_cityLabel (aproximada)'
        : (_locationIsApproximate ? 'Localização aproximada' : _cityLabel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _selectedPoint ?? _fallbackPoint,
                    initialZoom: 15,
                    onPositionChanged: (camera, hasGesture) {
                      final center = camera.center;
                      _selectedPoint = center;
                      _reverseGeocodeDebounce?.cancel();
                      _reverseGeocodeDebounce = Timer(
                        const Duration(milliseconds: 500),
                        () => _updateAddressFromPoint(center),
                      );
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.meu_app',
                    ),
                  ],
                ),
                const IgnorePointer(child: _CenterPin()),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x220D1520),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        _isResolvingAddress || _isLoadingLocation
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.location_on_rounded,
                                color: UrbColors.violet,
                                size: 18,
                              ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _isResolvingAddress
                                    ? 'Atualizando endereço...'
                                    : _locationLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: UrbText.body(
                                  size: 13,
                                  weight: FontWeight.w700,
                                  color: UrbColors.ink,
                                  height: 1.3,
                                ),
                              ),
                              Text(
                                cityText,
                                style: UrbText.body(
                                  size: 12,
                                  color: _locationIsApproximate
                                      ? const Color(0xFFB45309)
                                      : UrbColors.textMuted,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Campo para digitar o endereço, entre o mapa e o botão de localização.
        TextField(
          controller: _addressSearchController,
          onChanged: _onAddressQueryChanged,
          textInputAction: TextInputAction.search,
          textAlign: TextAlign.center,
          style: UrbText.body(size: 15, color: UrbColors.ink, height: 1.3),
          decoration: urbInputDecoration(
            hintText: 'Digite o endereço ou bairro',
            icon: Icons.search_rounded,
            suffix: _isSearchingAddress
                ? const Padding(
                    padding: EdgeInsets.all(15),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _addressSearchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar',
                    icon: const Icon(
                      Icons.close_rounded,
                      color: UrbColors.textMuted,
                      size: 20,
                    ),
                    onPressed: () {
                      _addressSearchController.clear();
                      _onAddressQueryChanged('');
                    },
                  ),
          ),
        ),
        // Sugestões de endereço aparecem deslizando embaixo do campo.
        AnimatedSize(
          duration: UrbMotion.of(context, UrbMotion.fast),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child:
              _addressResults.isEmpty &&
                  !(_addressSearchDone && !_isSearchingAddress)
              ? const SizedBox(width: double.infinity)
              : Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: UrbColors.border, width: 1.5),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x140D1520),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: _addressResults.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Nenhum endereço encontrado. Tente com o nome da rua e o bairro.',
                            textAlign: TextAlign.center,
                            style: UrbText.body(
                              size: 13,
                              color: UrbColors.textMuted,
                              height: 1.4,
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            for (
                              var i = 0;
                              i < _addressResults.length;
                              i++
                            ) ...[
                              if (i > 0)
                                const Divider(
                                  height: 1,
                                  color: UrbColors.border,
                                ),
                              InkWell(
                                onTap: () => _selectAddress(_addressResults[i]),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.location_on_outlined,
                                        size: 20,
                                        color: UrbColors.violet,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _addressResults[i].label,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: UrbText.body(
                                            size: 13,
                                            color: UrbColors.ink,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _isLoadingLocation ? null : _initializeLocation,
            icon: const Icon(Icons.my_location_rounded, size: 18),
            label: Text(
              'Usar minha localização',
              style: UrbText.body(
                size: 15,
                weight: FontWeight.w700,
                color: UrbColors.violetDeep,
                height: 1.2,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: UrbColors.violetDeep,
              side: const BorderSide(color: Color(0xFFD9D3F0), width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Arraste o mapa para ajustar o ponto exato do reporte.',
          textAlign: TextAlign.center,
          style: UrbText.body(
            size: 13,
            color: UrbColors.textMuted,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // Passo 3: categoria, órgão, anônimo e resumo.
  Widget _buildStepDetails() {
    final selectedCity = _selectedCity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PickerField(
          label: 'Categoria',
          icon: Icons.sell_outlined,
          value: _selectedCategory?.name,
          placeholder: _isLoadingLookups
              ? 'Carregando categorias...'
              : 'Selecione a categoria',
          onTap: _isLoadingLookups ? null : _chooseCategory,
        ),
        const SizedBox(height: 18),
        _PickerField(
          label: 'Órgão responsável (opcional)',
          icon: Icons.account_balance_outlined,
          value: _selectedAgency == null
              ? null
              : '${_selectedAgency!.name} (${_selectedAgency!.type})',
          placeholder: selectedCity == null
              ? 'Defina primeiro a cidade no mapa'
              : _agencies.isEmpty
              ? 'Nenhum órgão cadastrado em ${selectedCity.name}'
              : 'Selecione a secretaria responsável',
          onTap: selectedCity == null || _agencies.isEmpty
              ? null
              : _chooseAgency,
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color: UrbColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reportar em anônimo',
                      style: UrbText.body(
                        size: 15,
                        weight: FontWeight.w700,
                        color: UrbColors.ink,
                        height: 1.3,
                      ),
                    ),
                    Text(
                      'Ocultar o autor quando for publicado.',
                      style: UrbText.body(size: 13, height: 1.35),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _isAnonymous,
                activeThumbColor: Colors.white,
                activeTrackColor: UrbColors.violet,
                onChanged: (value) => setState(() => _isAnonymous = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Resumo',
          style: UrbText.body(
            size: 13,
            weight: FontWeight.w700,
            color: const Color(0xFF374151),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFECE8F8), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: UrbGradients.photo,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: _images.isEmpty
                      ? const Icon(
                          Icons.image_outlined,
                          color: Color(0xFF9FB0C6),
                        )
                      : Text(
                          '${_images.length}\nfoto${_images.length > 1 ? 's' : ''}',
                          textAlign: TextAlign.center,
                          style: UrbText.body(
                            size: 11,
                            weight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.2,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _titleController.text.trim().isEmpty
                          ? 'Sem título'
                          : _titleController.text.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.display(size: 16, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _locationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.body(
                        size: 12,
                        color: UrbColors.textMuted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: UrbGradients.gamification,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '+20 XP',
                style: UrbText.body(
                  size: 13,
                  weight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'ao publicar',
              style: UrbText.body(
                size: 13,
                weight: FontWeight.w700,
                color: UrbColors.violetDeep,
                height: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Comemoração depois de publicar.
  Widget _buildPublished() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: UrbMotion.of(context, const Duration(milliseconds: 600)),
            curve: Curves.elasticOut,
            builder: (context, value, child) =>
                Transform.scale(scale: value, child: child),
            child: Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x5510B981),
                    blurRadius: 0,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 46,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Reporte publicado!',
            textAlign: TextAlign.center,
            style: UrbText.display(size: 24, weight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            _publishedNote ?? 'Obrigado por cuidar da sua cidade.',
            textAlign: TextAlign.center,
            style: UrbText.body(size: 15),
          ),
          const SizedBox(height: 18),
          // O "+20 XP" sobe e aparece.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: UrbMotion.of(context, const Duration(milliseconds: 700)),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: child,
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                gradient: UrbGradients.gamification,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '+20 XP',
                style: UrbText.display(
                  size: 20,
                  weight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }
}

/// Mostra o passo com uma entrada suave quando ele vira o atual.
class _StepPane extends StatefulWidget {
  const _StepPane({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_StepPane> createState() => _StepPaneState();
}

class _StepPaneState extends State<_StepPane>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: widget.active ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _StepPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(24 * (1 - t), 0),
            child: child,
          ),
        );
      },
    );
  }
}

/// Pino fixo no centro do mapa.
class _CenterPin extends StatelessWidget {
  const _CenterPin();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 44),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: UrbGradients.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x553B3FA0),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          Container(width: 3, height: 12, color: const Color(0xFF3C57C4)),
          Container(
            width: 10,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Campo que abre uma janela de escolha (categoria, órgão...).
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.icon,
    required this.value,
    required this.placeholder,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String? value;
  final String placeholder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: UrbText.body(
            size: 13,
            weight: FontWeight.w700,
            color: const Color(0xFF374151),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Material(
          color: hasValue ? UrbColors.lavender : UrbColors.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasValue
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
                    color: hasValue
                        ? UrbColors.violetDeep
                        : UrbColors.textMuted,
                  ),
                  Expanded(
                    child: Text(
                      value ?? placeholder,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.body(
                        size: 15,
                        weight: hasValue ? FontWeight.w700 : FontWeight.w400,
                        color: hasValue
                            ? UrbColors.violetDeep
                            : UrbColors.textMuted,
                        height: 1.2,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.expand_more_rounded,
                    color: hasValue
                        ? UrbColors.violetDeep
                        : UrbColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Janela flutuante com lista e busca para escolher uma opção.
class _OptionPickerDialog<T> extends StatefulWidget {
  const _OptionPickerDialog({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.searchHint,
    required this.options,
    required this.labelOf,
    required this.isSelected,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String searchHint;
  final List<T> options;
  final String Function(T option) labelOf;
  final bool Function(T option) isSelected;

  @override
  State<_OptionPickerDialog<T>> createState() => _OptionPickerDialogState<T>();
}

class _OptionPickerDialogState<T> extends State<_OptionPickerDialog<T>> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final filter = _filter.trim().toLowerCase();
    final options = widget.options
        .where(
          (o) =>
              filter.isEmpty ||
              widget.labelOf(o).toLowerCase().contains(filter),
        )
        .toList();

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UrbDialogHeader(
              icon: widget.icon,
              title: widget.title,
              subtitle: widget.subtitle,
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 14),
            TextField(
              onChanged: (value) => setState(() => _filter = value),
              textAlign: TextAlign.center,
              style: UrbText.body(size: 15, color: UrbColors.ink, height: 1.3),
              decoration: urbInputDecoration(
                hintText: widget.searchHint,
                icon: Icons.search_rounded,
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final option in options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(option),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: widget.isSelected(option)
                                ? UrbColors.lavender
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: widget.isSelected(option)
                                  ? UrbColors.violet.withValues(alpha: 0.45)
                                  : UrbColors.border,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.labelOf(option),
                                  style: UrbText.body(
                                    size: 15,
                                    weight: FontWeight.w700,
                                    color: widget.isSelected(option)
                                        ? UrbColors.violetDeep
                                        : UrbColors.ink,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                              if (widget.isSelected(option))
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: UrbColors.violetDeep,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (options.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Nada encontrado.',
                        textAlign: TextAlign.center,
                        style: UrbText.body(
                          size: 14,
                          color: UrbColors.textMuted,
                        ),
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

/// Resultado da busca de endereço.
class _AddressResult {
  const _AddressResult({required this.label, required this.point});

  final String label;
  final LatLng point;
}
