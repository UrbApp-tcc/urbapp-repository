import 'package:flutter/material.dart';

import '../theme/urbapp_design.dart';
import 'city_skyline.dart';

/// Topo roxo do novo visual, com a cidade desenhada ao fundo e
/// cantos de baixo arredondados.
class UrbHero extends StatelessWidget {
  const UrbHero({
    super.key,
    required this.height,
    required this.child,
    this.onBack,
  });

  /// Altura sem contar a barra de status do aparelho.
  final double height;
  final Widget child;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Container(
      height: height + topInset,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: UrbColors.hero,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 160,
            child: CitySkyline(),
          ),
          Padding(
            padding: EdgeInsets.only(top: topInset),
            child: child,
          ),
          if (onBack != null)
            Positioned(
              left: 16,
              top: topInset + 10,
              child: UrbGlassButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Voltar',
                onPressed: onBack!,
              ),
            ),
        ],
      ),
    );
  }
}

/// Botão quadrado "de vidro" usado sobre o topo roxo (voltar, fechar...).
class UrbGlassButton extends StatelessWidget {
  const UrbGlassButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Logo do UrbApp recortado (o logo.png tem margem branca).
class UrbLogoTile extends StatelessWidget {
  const UrbLogoTile({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.23),
        boxShadow: const [
          BoxShadow(
            color: Color(0x730A0628),
            blurRadius: 34,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.23),
        child: Transform.scale(
          scale: 1.32,
          child: Image.asset(
            'assets/images/logo.png',
            fit: BoxFit.cover,
            semanticLabel: 'UrbApp',
          ),
        ),
      ),
    );
  }
}

/// Cartão branco que "sobe" por cima do topo roxo.
class UrbCard extends StatelessWidget {
  const UrbCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(22, 30, 22, 28),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x590A0628),
            blurRadius: 50,
            offset: Offset(0, 24),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Tela de acesso com o fundo roxo ocupando a tela inteira,
/// a cidade desenhada embaixo e o conteúdo centralizado.
class UrbAuthScaffold extends StatelessWidget {
  const UrbAuthScaffold({super.key, required this.child, this.onBack});

  final Widget child;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: UrbColors.hero,
      body: Stack(
        children: [
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 220,
            child: CitySkyline(),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  onBack == null ? 32 : 68,
                  20,
                  32,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight:
                        (constraints.maxHeight - (onBack == null ? 64 : 100))
                            .clamp(0.0, double.infinity),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (onBack != null)
            Positioned(
              left: 16,
              top: topInset + 12,
              child: UrbGlassButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Voltar',
                onPressed: onBack!,
              ),
            ),
        ],
      ),
    );
  }
}

/// Título e subtítulo brancos das telas de acesso.
class UrbAuthTitle extends StatelessWidget {
  const UrbAuthTitle({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: UrbText.display(
            size: 28,
            weight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: UrbText.body(size: 16, color: UrbColors.heroText, height: 1.5),
        ),
      ],
    );
  }
}

/// Linha "Não tem uma conta? Criar conta" sobre o fundo roxo.
class UrbAuthFooterLink extends StatelessWidget {
  const UrbAuthFooterLink({
    super.key,
    required this.text,
    required this.action,
    required this.onPressed,
  });

  final String text;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(text, style: UrbText.body(size: 15, color: UrbColors.heroText)),
        TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          child: Text(
            action,
            style:
                UrbText.body(
                  size: 15,
                  weight: FontWeight.w700,
                  color: Colors.white,
                ).copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white,
                ),
          ),
        ),
      ],
    );
  }
}
