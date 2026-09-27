import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../theme/urbapp_design.dart';
import '../../widgets/city_skyline.dart';
import '../../widgets/urb_primary_button.dart';

/// Primeiro acesso: 3 telas de apresentação + pedido de localização.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingPage {
  const _OnboardingPage({required this.title, required this.text});

  final String title;
  final String text;
}

const _pages = [
  _OnboardingPage(
    title: 'Sua cidade na palma da mão',
    text:
        'Encontrou um buraco, um poste apagado ou lixo acumulado? '
        'Tire uma foto e reporte em segundos.',
  ),
  _OnboardingPage(
    title: 'Apoie e acompanhe',
    text:
        'Apoie os reportes dos vizinhos e acompanhe cada etapa até o '
        'órgão responsável resolver.',
  ),
  _OnboardingPage(
    title: 'Ganhe XP e insígnias',
    text:
        'Cada reporte, apoio e comentário vale XP. Suba de nível e '
        'conquiste as 5 insígnias do UrbApp.',
  ),
  _OnboardingPage(
    title: 'Onde você está?',
    text:
        'Usamos sua localização só para marcar o lugar do problema no '
        'mapa e mostrar os reportes da sua cidade.',
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _requestingLocation = false;

  bool get _isLast => _page == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    _controller.nextPage(
      duration: UrbMotion.of(context, UrbMotion.medium),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _requestLocation() async {
    setState(() => _requestingLocation = true);
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
    } catch (_) {
      // Sem permissão o app continua funcionando; o mapa só não centraliza.
    } finally {
      if (mounted) setState(() => _requestingLocation = false);
    }
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_page];

    return Scaffold(
      backgroundColor: UrbColors.hero,
      body: Column(
        children: [
          // ---------- Parte roxa com a ilustração ----------
          Expanded(
            child: Stack(
              children: [
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 200,
                  child: CitySkyline(),
                ),
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                          child: TextButton(
                            onPressed: widget.onFinished,
                            style: TextButton.styleFrom(
                              foregroundColor: UrbColors.heroText,
                              minimumSize: const Size(48, 48),
                            ),
                            child: Text(
                              'Pular',
                              style: UrbText.body(
                                size: 15,
                                weight: FontWeight.w700,
                                color: UrbColors.heroText,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: PageView.builder(
                          controller: _controller,
                          itemCount: _pages.length,
                          onPageChanged: (i) => setState(() => _page = i),
                          itemBuilder: (context, i) => Center(
                            child: _PageVisual(index: i, active: i == _page),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ---------- Painel branco com o texto ----------
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: UrbMotion.of(context, UrbMotion.medium),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.12),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Column(
                        key: ValueKey(_page),
                        children: [
                          Text(
                            page.title,
                            textAlign: TextAlign.center,
                            style: UrbText.display(size: 28),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            page.text,
                            textAlign: TextAlign.center,
                            style: UrbText.body(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _Dots(count: _pages.length, current: _page),
                    const SizedBox(height: 20),
                    UrbPrimaryButton(
                      label: _isLast ? 'Permitir localização' : 'Continuar',
                      icon: _isLast
                          ? Icons.location_on_outlined
                          : Icons.arrow_forward_rounded,
                      loading: _requestingLocation,
                      onPressed: _isLast ? _requestLocation : _next,
                    ),
                    AnimatedSize(
                      duration: UrbMotion.of(context, UrbMotion.fast),
                      child: _isLast
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: TextButton(
                                onPressed: widget.onFinished,
                                child: Text(
                                  'Agora não',
                                  style: UrbText.body(
                                    size: 14,
                                    weight: FontWeight.w700,
                                    color: UrbColors.violetDeep,
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pontinhos de progresso: o atual "estica" com animação.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Passo ${current + 1} de $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final active = i == current;
          return AnimatedContainer(
            duration: UrbMotion.of(context, UrbMotion.fast),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: active ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: active ? UrbColors.violet : UrbColors.dotInactive,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

/// Ilustração de cada página. Anima ao entrar e fica parada depois
/// (menos o pulso da localização), para não pesar.
class _PageVisual extends StatefulWidget {
  const _PageVisual({required this.index, required this.active});

  final int index;
  final bool active;

  @override
  State<_PageVisual> createState() => _PageVisualState();
}

class _PageVisualState extends State<_PageVisual>
    with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  // Só a página de localização usa o pulso contínuo.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant _PageVisual oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _start();
    if (!widget.active && oldWidget.active) _pulse.stop();
  }

  void _start() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      if (reduceMotion) {
        _enter.value = 1;
        return;
      }
      _enter.forward(from: 0);
      if (widget.index == 3) _pulse.repeat();
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// Curva de entrada de cada elemento, com atraso escalonado.
  Animation<double> _step(
    double start,
    double end, [
    Curve curve = Curves.easeOutBack,
  ]) {
    return CurvedAnimation(
      parent: _enter,
      curve: Interval(start, end, curve: curve),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.index) {
      case 0:
        return _logo();
      case 1:
        return _card();
      case 2:
        return _badges();
      default:
        return _location();
    }
  }

  Widget _popIn(Animation<double> a, Widget child) {
    return AnimatedBuilder(
      animation: a,
      builder: (context, _) => Opacity(
        opacity: a.value.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.6 + 0.4 * a.value, child: child),
      ),
    );
  }

  // Página 1: o logo "cresce" na tela.
  Widget _logo() {
    return _popIn(
      _step(0, 0.8),
      Container(
        width: 190,
        height: 190,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(44),
          boxShadow: const [
            BoxShadow(
              color: Color(0x800A0628),
              blurRadius: 60,
              offset: Offset(0, 30),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(44),
          // O logo.png tem margem branca; o zoom recorta só o quadrado azul.
          child: Transform.scale(
            scale: 1.32,
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.cover,
              semanticLabel: 'UrbApp',
            ),
          ),
        ),
      ),
    );
  }

  // Página 2: o cartão entra, depois o coração e o balão "saltam".
  Widget _card() {
    return SizedBox(
      width: 270,
      height: 260,
      child: Stack(
        children: [
          Positioned(
            left: 20,
            top: 30,
            child: _popIn(
              _step(0, 0.55, Curves.easeOutCubic),
              Container(
                width: 230,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x730A0628),
                      blurRadius: 50,
                      offset: Offset(0, 24),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 110,
                      decoration: BoxDecoration(
                        gradient: UrbGradients.photo,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.image_outlined,
                        color: Color(0xFF9FB0C6),
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Poste apagado',
                      style: UrbText.display(size: 16, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: UrbColors.lavender,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Em análise',
                        style: UrbText.body(
                          size: 12,
                          weight: FontWeight.w700,
                          color: UrbColors.violetDeep,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: _popIn(
              _step(0.45, 1),
              _bubble(
                const Icon(
                  Icons.favorite_rounded,
                  color: UrbColors.heart,
                  size: 30,
                ),
                64,
              ),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 6,
            child: _popIn(
              _step(0.6, 1),
              _bubble(
                const Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: UrbColors.commentBlue,
                  size: 26,
                ),
                60,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(Widget icon, double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x590A0628),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: icon,
    );
  }

  // Página 3: as insígnias aparecem uma depois da outra, e depois o "+20 XP".
  Widget _badges() {
    const files = ['bronze', 'silver', 'gold', 'diamond', 'ametist'];
    const sizes = [52.0, 62.0, 78.0, 62.0, 52.0];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x660A0628),
                blurRadius: 50,
                offset: Offset(0, 24),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(files.length, (i) {
              final start = 0.08 * i;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _popIn(
                  _step(start, (start + 0.45).clamp(0.0, 1.0)),
                  Image.asset(
                    'assets/images/badges/badge-${files[i]}.png',
                    width: sizes[i],
                    height: sizes[i],
                    fit: BoxFit.contain,
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 22),
        _popIn(
          _step(0.55, 1),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              gradient: UrbGradients.gamification,
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x660A0628),
                  blurRadius: 26,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Text(
              '+20 XP',
              style: UrbText.display(size: 20, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  // Página 4: pino de localização com ondas pulsando.
  Widget _location() {
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  for (final offset in [0.0, 0.5])
                    _ring(((_pulse.value + offset) % 1.0)),
                ],
              );
            },
          ),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
          ),
          _popIn(
            _step(0, 0.7),
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                gradient: UrbGradients.gamification,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x730A0628),
                    blurRadius: 30,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: Colors.white,
                size: 38,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(double t) {
    final size = 100 + 140 * t;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35 * (1 - t)),
          width: 2,
        ),
      ),
    );
  }
}
