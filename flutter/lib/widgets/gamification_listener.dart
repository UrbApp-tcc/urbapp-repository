import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/urbapp_design.dart';
import 'urb_dialog.dart';
import 'urb_primary_button.dart';

/// Envolve a tela principal e escuta, em tempo real, as notificações
/// do usuário. Quando chega um "level_up" (criado pela função SQL
/// award_xp), mostra a janela "Você subiu de nível!" com a insígnia nova.
class GamificationListener extends StatefulWidget {
  const GamificationListener({super.key, required this.child});

  final Widget child;

  @override
  State<GamificationListener> createState() => _GamificationListenerState();
}

class _GamificationListenerState extends State<GamificationListener> {
  final SupabaseClient _supabase = Supabase.instance.client;
  RealtimeChannel? _channel;
  bool _isShowingDialog = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) _supabase.removeChannel(channel);
    super.dispose();
  }

  void _subscribe() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    _channel = _supabase
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) => _handleNotification(payload.newRecord),
        )
        .subscribe();
  }

  void _handleNotification(Map<String, dynamic> row) {
    if (!mounted || row['type'] != 'level_up') return;

    final data = (row['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    _showLevelUpDialog(
      notificationId: (row['id'] as num?)?.toInt(),
      newLevel: (data['new_level'] as num?)?.toInt() ?? 1,
      levelTitle: data['level_title'] as String? ?? '',
    );
  }

  Future<void> _showLevelUpDialog({
    required int? notificationId,
    required int newLevel,
    required String levelTitle,
  }) async {
    if (_isShowingDialog) return;
    _isShowingDialog = true;

    await showUrbDialog<void>(
      context: context,
      builder: (_) => _LevelUpDialog(level: newLevel, title: levelTitle),
    );

    _isShowingDialog = false;

    if (notificationId != null) {
      try {
        await _supabase
            .from('notifications')
            .update({'read_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', notificationId);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Insígnia que cada nível desbloqueia (mesma regra do banco).
const _badgeByLevel = {
  1: ('bronze', 'Bronze'),
  2: ('silver', 'Prata'),
  3: ('gold', 'Ouro'),
  4: ('diamond', 'Diamante'),
  5: ('ametist', 'Safira'),
};

class _LevelUpDialog extends StatefulWidget {
  const _LevelUpDialog({required this.level, required this.title});

  final int level;
  final String title;

  @override
  State<_LevelUpDialog> createState() => _LevelUpDialogState();
}

class _LevelUpDialogState extends State<_LevelUpDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _step(double start, double end, Curve curve) =>
      CurvedAnimation(
        parent: _controller,
        curve: Interval(start, end, curve: curve),
      );

  @override
  Widget build(BuildContext context) {
    final badge = _badgeByLevel[widget.level];
    final circle = _step(0, 0.45, Curves.elasticOut);
    final coin = _step(0.4, 0.9, Curves.easeOutBack);
    final confetti = _step(0, 1, Curves.easeOut);

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Topo em gradiente com confete e o número do nível.
          SizedBox(
            height: 170,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: UrbGradients.primary),
                  ),
                ),
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: confetti,
                    builder: (context, _) =>
                        CustomPaint(painter: _ConfettiPainter(confetti.value)),
                  ),
                ),
                AnimatedBuilder(
                  animation: circle,
                  builder: (context, child) =>
                      Transform.scale(scale: circle.value, child: child),
                  child: Container(
                    width: 108,
                    height: 108,
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: UrbGradients.gamification,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x660A0628),
                          blurRadius: 30,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${widget.level}',
                        style: UrbText.display(
                          size: 50,
                          weight: FontWeight.w800,
                          color: UrbColors.violetDeep,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'NOVO NÍVEL',
                  textAlign: TextAlign.center,
                  style: UrbText.body(
                    size: 12,
                    weight: FontWeight.w700,
                    color: UrbColors.violet,
                    height: 1.3,
                  ).copyWith(letterSpacing: 1.4),
                ),
                const SizedBox(height: 4),
                Text(
                  'Você subiu de nível!',
                  textAlign: TextAlign.center,
                  style: UrbText.display(size: 26, weight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(
                    text: 'Parabéns! Você chegou ao nível ${widget.level}',
                    children: [
                      if (widget.title.isNotEmpty) ...[
                        const TextSpan(text: ': '),
                        TextSpan(
                          text: widget.title,
                          style: UrbText.body(
                            size: 15,
                            weight: FontWeight.w700,
                            color: UrbColors.ink,
                            height: 1.45,
                          ),
                        ),
                      ],
                      const TextSpan(text: '.'),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: UrbText.body(size: 15, height: 1.45),
                ),
                if (badge != null) ...[
                  const SizedBox(height: 16),
                  // A insígnia gira como uma moeda antes de aparecer.
                  AnimatedBuilder(
                    animation: coin,
                    builder: (context, child) {
                      final t = coin.value.clamp(0.0, 1.0);
                      return Opacity(
                        opacity: t,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.002)
                            ..rotateY((1 - t) * math.pi),
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: UrbColors.surface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/images/badges/badge-${badge.$1}.png',
                            width: 48,
                            height: 48,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              'Insígnia ${badge.$2} desbloqueada',
                              style: UrbText.body(
                                size: 14,
                                weight: FontWeight.w700,
                                color: const Color(0xFF374151),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                UrbPrimaryButton(
                  label: 'Continuar',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Confete leve: poucos pontinhos que se espalham e somem.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.progress);

  final double progress;

  static const _colors = [
    Color(0xFFFFFFFF),
    Color(0xFFF6D365),
    Color(0xFF9A80D9),
    Color(0xFF40B4F5),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint();
    for (var i = 0; i < 18; i++) {
      final angle = (i / 18) * math.pi * 2;
      final distance = 40 + 110 * progress * (0.6 + 0.4 * ((i * 37) % 10) / 10);
      final position =
          center +
          Offset(math.cos(angle) * distance, math.sin(angle) * distance * 0.7);
      paint.color = _colors[i % _colors.length].withValues(alpha: 1 - progress);
      canvas.drawCircle(position, 3.5, paint);
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
