import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../main.dart';
import '../utils/design_system.dart';
import '../widgets/app_container.dart';

class ServerListScreen extends StatefulWidget {
  const ServerListScreen({super.key});

  @override
  State<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends State<ServerListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  String _search = '';
  final _searchCtrl = TextEditingController();

  final _tabs = ['All', 'Streaming', 'Gaming', 'Crypto', 'Pro'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<dynamic> _filtered(List<dynamic> allServers, String tab) {
    final tabKey = tab.toLowerCase();
    return allServers.where((s) {
      final matchesSearch = _search.isEmpty ||
          s['country'].toString().toLowerCase().contains(_search.toLowerCase()) ||
          s['city'].toString().toLowerCase().contains(_search.toLowerCase()) ||
          s['name'].toString().toLowerCase().contains(_search.toLowerCase());
      
      final matchesTab = tabKey == 'all'
          ? true
          : tabKey == 'pro'
              ? s['plan'] == 'pro'
              : s['types'] != null && (s['types'][tabKey] == true);
      
      return matchesSearch && matchesTab;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VPNProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppContainer(
        child: Column(
          children: [
            // Header
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.cardBackground,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Select Server',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -0.5),
                        ),
                        Text(
                          '${provider.servers.length} locations available',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.map_outlined, color: AppColors.primaryBlue),
                    ),
                  ],
                ),
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.all(20),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  onChanged: (v) => setState(() => _search = v),
                  decoration: const InputDecoration(
                    hintText: 'Search by country or city...',
                    hintStyle: TextStyle(color: AppColors.textSecondary),
                    prefixIcon: Icon(Icons.search_rounded, color: AppColors.textSecondary),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(20),
                  ),
                ),
              ),
            ),

            // Tabs
            TabBar(
              controller: _tabCtrl,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.symmetric(horizontal: 24),
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              labelColor: AppColors.primaryBlue,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primaryBlue,
              dividerColor: Colors.transparent,
              tabs: _tabs.map((t) => Tab(text: t)).toList(),
            ),

            const SizedBox(height: 10),

            // Server List
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: _tabs.map((tab) {
                  final list = _filtered(provider.servers, tab);
                  if (list.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.dns_rounded, color: AppColors.textSecondary.withValues(alpha: 0.2), size: 80),
                          const SizedBox(height: 20),
                          const Text('No servers matches your criteria', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _ServerCard(
                      server: list[i],
                      onConnect: () {
                        provider.connect(list[i]['id'].toString());
                        Navigator.pop(context);
                      },
                    ).animate().fadeIn(delay: (i * 50).ms).slideX(begin: 0.1, end: 0),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerCard extends StatefulWidget {
  final Map<String, dynamic> server;
  final VoidCallback onConnect;
  const _ServerCard({required this.server, required this.onConnect});

  @override
  State<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<_ServerCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isPro = widget.server['plan'] == 'pro';
    final ping = widget.server['ping_ms'] ?? 0;
    
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onConnect,
        child: AnimatedContainer(
          duration: 200.ms,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isHovered ? AppColors.primaryBlue.withValues(alpha: 0.05) : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isHovered ? AppColors.primaryBlue.withValues(alpha: 0.3) : AppColors.divider,
            ),
          ),
          child: Row(
            children: [
              // Flag
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(widget.server['flag'] ?? '🏳️', style: const TextStyle(fontSize: 24)),
              ),
              
              const SizedBox(width: 16),
              
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.server['country'] ?? 'Unknown',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        if (isPro) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('PRO', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      widget.server['city'] ?? 'Unknown',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),

              // Ping & Status
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      _buildSignalBars(ping),
                      const SizedBox(width: 8),
                      Text(
                        '${ping}ms',
                        style: TextStyle(
                          color: ping < 50 ? AppColors.success : (ping < 100 ? Colors.amber : AppColors.warning),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignalBars(int ping) {
    Color color = ping < 50 ? AppColors.success : (ping < 100 ? Colors.amber : AppColors.warning);
    int bars = ping < 50 ? 4 : (ping < 100 ? 3 : 2);
    
    return Row(
      children: List.generate(4, (i) {
        return Container(
          width: 3,
          height: 6.0 + (i * 3),
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: i < bars ? color : AppColors.textSecondary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
