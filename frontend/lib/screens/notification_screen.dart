import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../utils/api_service.dart';
import '../utils/design_system.dart';
import '../widgets/app_container.dart';
import '../main.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<dynamic> _notifications = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  final int _limit = 20;
  bool _unreadOnly = false;
  int _unreadCount = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchNotifications();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _fetchMoreNotifications();
    }
  }

  Future<void> _fetchNotifications() async {
    setState(() {
      _isLoading = true;
      _page = 1;
    });
    try {
      final response = await ApiService.getNotifications(
          unreadOnly: _unreadOnly, page: _page, limit: _limit);
      if (response['success'] == true) {
        setState(() {
          _notifications = response['data']['notifications'] ?? [];
          _unreadCount = response['data']['unread_count'] ?? 0;
          _hasMore = response['data']['has_more'] ?? false;
          _isLoading = false;
        });
        if (mounted) {
          context.read<VPNProvider>().fetchNotifications();
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMoreNotifications() async {
    setState(() => _isLoadingMore = true);
    try {
      final nextPage = _page + 1;
      final response = await ApiService.getNotifications(
          unreadOnly: _unreadOnly, page: nextPage, limit: _limit);
      if (response['success'] == true) {
        setState(() {
          final newNotifs = response['data']['notifications'] ?? [];
          _notifications.addAll(newNotifs);
          _unreadCount = response['data']['unread_count'] ?? 0;
          _hasMore = response['data']['has_more'] ?? false;
          _page = nextPage;
          _isLoadingMore = false;
        });
      } else {
        setState(() => _isLoadingMore = false);
      }
    } catch (e) {
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _markAsRead(String id) async {
    try {
      final response = await ApiService.markNotificationRead(id);
      if (response['success'] == true) {
        _fetchNotifications();
      }
    } catch (_) {}
  }

  Future<void> _markAllAsRead() async {
    try {
      final response = await ApiService.markAllNotificationsRead();
      if (response['success'] == true) {
        _fetchNotifications();
      }
    } catch (_) {}
  }

  Future<void> _deleteNotification(String id) async {
    try {
      final response = await ApiService.deleteNotification(id);
      if (response['success'] == true) {
        _fetchNotifications();
      }
    } catch (_) {}
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'security':
        return Icons.security_rounded;
      case 'vpn_event':
        return Icons.link_off_rounded;
      case 'login':
        return Icons.devices_rounded;
      case 'bandwidth':
        return Icons.warning_amber_rounded;
      case 'upgrade':
        return Icons.star_rounded;
      case 'coming_soon':
        return Icons.auto_awesome_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'security':
        return AppColors.primaryBlue;
      case 'vpn_event':
        return AppColors.warning;
      case 'login':
        return AppColors.accentPurple;
      case 'bandwidth':
        return Colors.orangeAccent;
      case 'upgrade':
        return AppColors.neonCyan;
      case 'coming_soon':
        return AppColors.accentPurple;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Notifications',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text('Mark all as read',
                  style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: AppContainer(
        child: Column(
          children: [
            _buildFilterBar(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryBlue))
                  : _notifications.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _fetchNotifications,
                          color: AppColors.primaryBlue,
                          backgroundColor: AppColors.cardBackground,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(20),
                            itemCount: _notifications.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _notifications.length) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: CircularProgressIndicator(color: AppColors.primaryBlue),
                                  ),
                                );
                              }
                              final notif = _notifications[index];
                              return _buildNotificationCard(notif, index);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          _filterChip('All', !_unreadOnly, () {
            setState(() => _unreadOnly = false);
            _fetchNotifications();
          }),
          const SizedBox(width: 12),
          _filterChip('Unread', _unreadOnly, () {
            setState(() => _unreadOnly = true);
            _fetchNotifications();
          }),
          const Spacer(),
          if (_unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$_unreadCount unread',
                style: const TextStyle(color: AppColors.primaryBlue, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryBlue : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? AppColors.primaryBlue : AppColors.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notif, int index) {
    final type = notif['type'] ?? 'security';
    final isRead = notif['is_read'] ?? false;
    final color = _getColorForType(type);
    final icon = _getIconForType(type);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isRead ? AppColors.cardBackground : AppColors.cardBackground.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isRead ? AppColors.divider : color.withOpacity(0.3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: isRead ? null : () => _markAsRead(notif['id']),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              notif['title'] ?? 'Notification',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Text(
                            notif['time_ago'] ?? '',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        notif['message'] ?? '',
                        style: TextStyle(
                          color: isRead ? AppColors.textSecondary : Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      if (notif['coming_soon'] == true)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accentPurple.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'COMING SOON',
                            style: TextStyle(color: AppColors.accentPurple, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isRead)
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 16),
                      onPressed: () => _deleteNotification(notif['id']),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: (index * 50).ms).slideX(begin: 0.1, end: 0);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none_rounded, color: AppColors.textSecondary.withOpacity(0.3), size: 80),
          const SizedBox(height: 24),
          const Text(
            'All caught up!',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'You have no new notifications.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ).animate().fadeIn(),
    );
  }
}
