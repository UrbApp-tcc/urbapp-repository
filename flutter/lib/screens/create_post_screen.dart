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
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/gradient_button.dart';
import '../widgets/media_picker_widget.dart';
import '../widgets/wave_header.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key, this.returnToPreviousOnSuccess = false});

  final bool returnToPreviousOnSuccess;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _formKey = GlobalKey<FormState>();
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
  String? _resolvedStateCode;
  bool _locationIsApproximate = false;

  bool _isAnonymous = false;
  bool _isSubmitting = false;
  bool _isLoadingLookups = true;
  bool _isLoadingLocation = true;
  bool _isResolvingAddress = false;

  Timer? _reverseGeocodeDebounce;

  static const double _maxContentWidth = 440;
  static const double _fieldSpacing = 16;
  static const LatLng _fallbackPoint = LatLng(-23.55052, -46.63331);

  @override
  void initState() {
    super.initState();
    _loadLookups();
  }

  @override
  void dispose() {
    _reverseGeocodeDebounce?.cancel();
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
      _showError(error.toString().replaceFirst('Exception: ', ''));
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

      _mapController.move(point, 16);
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
        _resolvedStateCode = null;
        _locationIsApproximate = true;
      });

      _mapController.move(_fallbackPoint, 13);
      _showError(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  String? _validateRequired(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return 'Informe $label';
    }
    return null;
  }

  String get _currentUserLabel {
    return _authService.currentUser?.email ?? 'Usuario autenticado';
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

      debugPrint(
        'Location match: point=(${point.latitude}, ${point.longitude}) '
        'street="$street" neighborhood="$neighborhood" locality="$locality" '
        'state="${locationData.state}" stateCode="$stateCode" '
        'matchedCity="${matchedCity?.name}" loadedCities=${_cities.length}',
      );

      if (!mounted) return;

      setState(() {
        _selectedPoint = point;
        _selectedCity = matchedCity;
        _selectedAgency = null;
        _cityLabel = locality.isNotEmpty ? locality : 'Cidade nao identificada';
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

      debugPrint(
        'Location UI state: label="$_locationLabel" cityLabel="$_cityLabel" '
        'approximate=$_locationIsApproximate cityId=${_selectedCity?.id}',
      );
    } catch (error, stackTrace) {
      debugPrint('Reverse geocoding failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;

      setState(() {
        _selectedPoint = point;
        _selectedCity = null;
        _selectedAgency = null;
        _agencies = const [];
        _cityLabel = 'Cidade nao identificada';
        _locationLabel = 'Localizacao aproximada';
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

    debugPrint(
      'City match not found for "$cityName" (normalized="$normalizedTarget", state="$stateCode"). '
      'Loaded cities sample: ${_cities.take(10).map((city) => city.name).join(', ')}',
    );
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
        debugPrint('Placemark retorno: $placemarks');

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
      } catch (error, stackTrace) {
        debugPrint('placemarkFromCoordinates falhou: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
        'zoom': '18',
        'addressdetails': '1',
      });

      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw Exception('Falha ao consultar o endereco no mapa.');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final address = (data['address'] as Map<String, dynamic>?) ?? const {};
      debugPrint('Reverse geocoding result: $address');

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
    } catch (error, stackTrace) {
      debugPrint('HTTP reverse geocoding falhou: $error');
      debugPrintStack(stackTrace: stackTrace);
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
    if (!_formKey.currentState!.validate()) return;

    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      _showError(
        'Sua sessao expirou. Entre novamente para publicar o reporte.',
      );
      return;
    }

    if (_selectedPoint == null) {
      _showError('Aguarde o mapa carregar ou escolha um ponto no mapa.');
      return;
    }

    final matchedCity = await _resolveCityForSubmission();

    if (_selectedCategory == null) {
      _showError('Selecione uma categoria.');
      return;
    }

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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _images.isEmpty
                ? 'Reporte criado com sucesso!'
                : 'Reporte criado com imagens com sucesso!',
          ),
          backgroundColor: AppColors.resolved,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );

      _formKey.currentState!.reset();
      _titleController.clear();
      _descriptionController.clear();
      _categorySearchController.clear();

      setState(() {
        _isAnonymous = false;
        _selectedCity = matchedCity;
        _selectedCategory = null;
        _selectedAgency = null;
        _images = [];
        _resolvedStateCode = null;
        _locationIsApproximate = false;
      });

      if (matchedCity == null) {
        _showInfo('Reporte publicado com localizacao aproximada.');
      }

      if (widget.returnToPreviousOnSuccess &&
          mounted &&
          Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      _showError(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showInfo(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.inProgress,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            children: [
              WaveHeader(
                height: 220,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _buildHeaderContent(),
                  ),
                ),
              ),
              const AppLogo(height: 100),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                    child: _buildFormCard(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderContent() {
    return Stack(
      children: [
        if (Navigator.of(context).canPop())
          Positioned(
            top: 0,
            left: 0,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
          ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            const Text(
              'Criar um Reporte!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Registre um novo reporte para ajudar a comunidade a resolver problemas.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
        border: Border.all(color: AppColors.border),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Detalhes do reporte',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Preencha os campos abaixo para registrar um novo reporte.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionLabel('Identificacao'),
            const SizedBox(height: 24),
            _buildAnonymousCard(),
            const SizedBox(height: 12),
            _buildAuthenticatedUserCard(),
            const SizedBox(height: 24),
            _buildSectionLabel('Categoria'),
            const SizedBox(height: 12),
            _buildLookupField(
              label: 'Categoria',
              controller: _categorySearchController,
              options: _categories,
              selectedOption: _selectedCategory,
              loading: _isLoadingLookups,
              icon: Icons.category_outlined,
              emptyMessage: 'Nenhuma categoria encontrada.',
              onSelected: (option) {
                setState(() {
                  _selectedCategory = option;
                  _categorySearchController.text = option.name;
                });
              },
            ),
            const SizedBox(height: 24),
            _buildSectionLabel('Orgao responsavel'),
            const SizedBox(height: 12),
            _buildAgencySelector(),
            const SizedBox(height: 24),
            _buildSectionLabel('Conteudo'),
            const SizedBox(height: 12),
            AuthTextField(
              controller: _titleController,
              validator: (value) => _validateRequired(value, 'o titulo'),
              hintText: 'Titulo',
              prefixIcon: const Icon(Icons.title_rounded, size: 22),
            ),
            const SizedBox(height: _fieldSpacing),
            TextFormField(
              controller: _descriptionController,
              validator: (value) => _validateRequired(value, 'a descricao'),
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 5,
              maxLines: 7,
              decoration: const InputDecoration(
                hintText: 'Detalhe o seu problema',
                fillColor: AppColors.background,
                filled: true,
                contentPadding: EdgeInsets.fromLTRB(16, 18, 16, 18),
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 74),
                  child: Icon(Icons.description_outlined, size: 22),
                ),
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            MediaPickerWidget(
              images: _images,
              onChanged: (images) {
                setState(() {
                  _images = images;
                });
              },
            ),
            const SizedBox(height: 24),
            _buildSectionLabel('Localizacao'),
            const SizedBox(height: 12),
            _buildLocationCard(),
            const SizedBox(height: 28),
            GradientButton(
              label: 'Publicar reporte',
              loading: _isSubmitting,
              onPressed: (_isLoadingLookups || _isLoadingLocation)
                  ? null
                  : _submitPost,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnonymousCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.visibility_off_outlined,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reportar em anonimo',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Ocultar o autor do reporte quando ele for publicado.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _isAnonymous,
            activeThumbColor: AppColors.primary,
            onChanged: (value) => setState(() => _isAnonymous = value),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthenticatedUserCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Usuario autenticado',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _currentUserLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgencySelector() {
    final selectedCity = _selectedCity;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Selecione a secretaria ou orgao que deve receber esse chamado. Esse vinculo e opcional, mas ajuda a prefeitura a assumir o reporte.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int?>(
            initialValue: _selectedAgency?.id,
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Nenhum orgao vinculado'),
              ),
              ..._agencies.map(
                (agency) => DropdownMenuItem<int?>(
                  value: agency.id,
                  child: Text('${agency.name} (${agency.type})'),
                ),
              ),
            ],
            onChanged: selectedCity == null
                ? null
                : (value) {
                    setState(() {
                      _selectedAgency = value == null
                          ? null
                          : _agencies.firstWhere((agency) => agency.id == value);
                    });
                  },
            decoration: InputDecoration(
              labelText: 'Secretaria/orgao',
              hintText: selectedCity == null
                  ? 'Defina primeiro a cidade do reporte no mapa'
                  : _agencies.isEmpty
                      ? 'Nenhuma secretaria cadastrada para ${selectedCity.name}'
                      : 'Selecione a secretaria responsavel',
              prefixIcon: const Icon(Icons.account_balance_outlined, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.place_outlined,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isResolvingAddress
                          ? 'Atualizando endereco...'
                          : _locationLabel,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _locationIsApproximate &&
                              _cityLabel != 'Localizacao nao identificada'
                          ? '$_cityLabel (aproximada)'
                          : (_locationIsApproximate
                                ? 'Localizacao aproximada'
                                : _cityLabel),
                      style: TextStyle(
                        color: _locationIsApproximate
                            ? AppColors.pending
                            : AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Usar minha localizacao',
                onPressed: _isLoadingLocation ? null : _initializeLocation,
                icon: const Icon(Icons.my_location_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 260,
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
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.meu_app',
                      ),
                    ],
                  ),
                  IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_pin,
                          size: 42,
                          color: AppColors.accentPink,
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'O pin fica travado no centro. Arraste o mapa para ajustar o ponto exato do reporte.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLookupField({
    required String label,
    required TextEditingController controller,
    required List<LookupOption> options,
    required LookupOption? selectedOption,
    required bool loading,
    required IconData icon,
    required String emptyMessage,
    required ValueChanged<LookupOption> onSelected,
  }) {
    return Autocomplete<LookupOption>(
      displayStringForOption: (option) => option.name,
      optionsBuilder: (textEditingValue) {
        if (loading) {
          return const Iterable<LookupOption>.empty();
        }

        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) {
          return options.take(8);
        }

        return options.where(
          (option) =>
              option.name.toLowerCase().contains(query) ||
              option.id.toString().contains(query),
        );
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, textController, focusNode, onSubmitted) {
        textController.value = controller.value;

        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          validator: (_) {
            if (selectedOption == null) {
              return 'Selecione ${label.toLowerCase()} na lista';
            }
            return null;
          },
          onChanged: (value) {
            controller.value = textController.value;
            if (selectedOption != null && value.trim() != selectedOption.name) {
              setState(() => _selectedCategory = null);
            }
          },
          decoration: InputDecoration(
            hintText: loading ? 'Carregando $label...' : 'Pesquisar $label',
            fillColor: AppColors.background,
            filled: true,
            prefixIcon: Icon(icon, size: 22),
            suffixIcon: loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : selectedOption != null
                    ? const Icon(Icons.check_circle, color: AppColors.resolved)
                    : const Icon(Icons.search_rounded),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, optionsList) {
        final items = optionsList.toList();

        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: MediaQuery.sizeOf(context).width - 48,
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          emptyMessage,
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final option = items[index];
                        return ListTile(
                          title: Text(option.name),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.primaryDark,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
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
