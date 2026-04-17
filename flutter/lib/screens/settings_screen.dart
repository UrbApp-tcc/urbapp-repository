import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.currentUser,
    required this.onOpenSearch,
    required this.onSignOut,
  });

  final User? currentUser;
  final VoidCallback onOpenSearch;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final displayName = _displayName();
    final email = currentUser?.email ?? 'Conta conectada';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 132),
      children: [
        _SettingsTopBar(onOpenSearch: onOpenSearch),
        const SizedBox(height: 28),
        const Text(
          'Settings',
          style: TextStyle(
            color: Color(0xFF141E28),
            fontSize: 36,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 28),
        _ProfilePreviewCard(
          displayName: displayName,
          email: email,
        ),
        const SizedBox(height: 22),
        _SettingsItem(
          icon: Icons.person_outline_rounded,
          title: 'Profile settings',
          subtitle: 'Settings regarding your profile',
          onTap: () => _showProfileSheet(context, displayName, email),
        ),
        const SizedBox(height: 28),
        OutlinedButton.icon(
          onPressed: onSignOut,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sair da conta'),
        ),
      ],
    );
  }

  String _displayName() {
    final metadata = currentUser?.userMetadata ?? const {};
    final fullName = metadata['full_name']?.toString().trim();
    final username = metadata['username']?.toString().trim();
    final email = currentUser?.email?.trim();

    if (fullName != null && fullName.isNotEmpty) return fullName;
    if (username != null && username.isNotEmpty) return username;
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return 'Usuario UrbApp';
  }

  void _showProfileSheet(BuildContext context, String displayName, String email) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Profile settings',
                style: TextStyle(
                  color: Color(0xFF141E28),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              _SheetInfo(label: 'Nome', value: displayName),
              const SizedBox(height: 14),
              _SheetInfo(label: 'E-mail', value: email),
              const SizedBox(height: 14),
              _SheetInfo(
                label: 'Status',
                value: 'Tela inicial pronta para futuras configuracoes de perfil',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsTopBar extends StatelessWidget {
  const _SettingsTopBar({
    required this.onOpenSearch,
  });

  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Color(0xFF18222E),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.remove_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onOpenSearch,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF18222E), width: 1.6),
            ),
            child: const Icon(
              Icons.search_rounded,
              color: Color(0xFF18222E),
              size: 22,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfilePreviewCard extends StatelessWidget {
  const _ProfilePreviewCard({
    required this.displayName,
    required this.email,
  });

  final String displayName;
  final String email;

  @override
  Widget build(BuildContext context) {
    final initials = displayName
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word[0])
        .join()
        .toUpperCase();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Color(0xFF18222E),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initials.isEmpty ? 'U' : initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF141E28),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8F949D),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F6),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: const Color(0xFF141E28),
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF141E28),
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFFB3B7BE),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFB9BEC6), width: 1.4),
              ),
              child: const Icon(
                Icons.arrow_forward_rounded,
                size: 14,
                color: Color(0xFFB9BEC6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetInfo extends StatelessWidget {
  const _SheetInfo({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8F949D),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF141E28),
            fontSize: 16,
            height: 1.4,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
