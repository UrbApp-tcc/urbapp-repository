import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/feed_service.dart';
import '../theme/app_theme.dart';
import 'create_post_screen.dart';
import 'feed_screen.dart';
import 'notifications_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class AppShellScreen extends StatefulWidget {
  const AppShellScreen({super.key});

  @override
  State<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends State<AppShellScreen> {
  final _feedService = FeedService();
  final _authService = AuthService();

  int _selectedIndex = 0;
  List<FeedPost> _posts = const [];
  bool _isLoading = true;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  Future<void> _loadFeed({bool refreshing = false}) async {
    if (refreshing) {
      setState(() => _isRefreshing = true);
    } else {
      setState(() => _isLoading = true);
    }

    try {
      final posts = await _feedService.fetchFeed();

      if (!mounted) return;
      setState(() {
        _posts = posts;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _openCreatePost() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const CreatePostScreen(returnToPreviousOnSuccess: true),
      ),
    );

    if (!mounted || created != true) return;

    setState(() => _selectedIndex = 0);
    await _loadFeed(refreshing: true);
  }

  Future<void> _signOut() async {
    try {
      await _authService.signOut();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  void _selectTab(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F8),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useFramedLayout = constraints.maxWidth > 520;
            final shellWidth = constraints.maxWidth > 430 ? 390.0 : constraints.maxWidth;

            return Center(
              child: Container(
                width: shellWidth,
                margin: EdgeInsets.symmetric(
                  horizontal: useFramedLayout ? 16 : 0,
                  vertical: useFramedLayout ? 18 : 0,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(useFramedLayout ? 34 : 0),
                  boxShadow: useFramedLayout
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 34,
                            offset: const Offset(0, 18),
                          ),
                        ]
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: [
                          FeedScreen(
                            posts: _posts,
                            isLoading: _isLoading,
                            isRefreshing: _isRefreshing,
                            onCreatePost: _openCreatePost,
                          ),
                          SearchScreen(
                            posts: _posts,
                            isLoading: _isLoading,
                          ),
                          NotificationsScreen(
                            posts: _posts,
                            isLoading: _isLoading,
                            onOpenSearch: () => _selectTab(1),
                          ),
                          SettingsScreen(
                            currentUser: _authService.currentUser,
                            onOpenSearch: () => _selectTab(1),
                            onSignOut: _signOut,
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 44,
                      right: 44,
                      bottom: 24,
                      child: _ShellBottomBar(
                        selectedIndex: _selectedIndex,
                        onSelect: _selectTab,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 36,
                      child: Center(
                        child: GestureDetector(
                          onTap: _openCreatePost,
                          child: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: AppColors.accentPink,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.accentPink.withValues(alpha: 0.28),
                                  blurRadius: 24,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ShellBottomBar extends StatelessWidget {
  const _ShellBottomBar({
    required this.selectedIndex,
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF141E28).withValues(alpha: 0.14),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _BottomIconButton(
              icon: Icons.home_outlined,
              isSelected: selectedIndex == 0,
              onTap: () => onSelect(0),
            ),
          ),
          Expanded(
            child: _BottomIconButton(
              icon: Icons.search_rounded,
              isSelected: selectedIndex == 1,
              onTap: () => onSelect(1),
            ),
          ),
          const SizedBox(width: 44),
          Expanded(
            child: _BottomIconButton(
              icon: Icons.notifications_none_rounded,
              isSelected: selectedIndex == 2,
              onTap: () => onSelect(2),
            ),
          ),
          Expanded(
            child: _BottomIconButton(
              icon: Icons.settings_outlined,
              isSelected: selectedIndex == 3,
              onTap: () => onSelect(3),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomIconButton extends StatelessWidget {
  const _BottomIconButton({
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 64,
        child: Icon(
          icon,
          size: 25,
          color: isSelected ? const Color(0xFF141E28) : const Color(0xFFA2A7AF),
        ),
      ),
    );
  }
}
