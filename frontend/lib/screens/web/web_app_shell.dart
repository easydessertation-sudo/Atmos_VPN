import 'package:flutter/material.dart';
import '../../utils/design_system.dart';
import '../../main.dart';
import 'package:provider/provider.dart';

/// Desktop sidebar shell — wraps all post-login web pages
class WebAppShell extends StatefulWidget {
  final int selectedIndex;
  final Widget child;
  const WebAppShell({super.key, required this.selectedIndex, required this.child});

  @override
  State<WebAppShell> createState() => _WebAppShellState();
}

class _WebAppShellState extends State<WebAppShell> {
  bool _sidebarExpanded = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          _Sidebar(
            selectedIndex: widget.selectedIndex,
            expanded: _sidebarExpanded,
            onToggle: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final int selectedIndex;
  final bool expanded;
  final VoidCallback onToggle;
  const _Sidebar({required this.selectedIndex, required this.expanded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final w = expanded ? 240.0 : 72.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: w,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E1A),
        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Column(
        children: [
          // Logo
          Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.shield_rounded, color: Colors.white, size: 18),
                ),
                if (expanded) ...[
                  const SizedBox(width: 12),
                  const Text('SecureVPN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
                  const Spacer(),
                ],
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 16),
          // Nav Items
          _NavItem(icon: Icons.home_rounded,         label: 'Dashboard',  route: '/dashboard', index: 0, selected: selectedIndex == 0, expanded: expanded),
          _NavItem(icon: Icons.public_rounded,         label: 'Servers',    route: '/server-list', index: 1, selected: selectedIndex == 1, expanded: expanded),
          _NavItem(icon: Icons.bolt_rounded,           label: 'Modes',      route: '/modes', index: 2, selected: selectedIndex == 2, expanded: expanded),
          _NavItem(icon: Icons.security_rounded,       label: 'Security',   route: '/security', index: 3, selected: selectedIndex == 3, expanded: expanded),
          _NavItem(icon: Icons.speed_rounded,          label: 'Speed Test', route: '/speed', index: 4, selected: selectedIndex == 4, expanded: expanded),
          const SizedBox(height: 8),
          const Divider(color: Colors.white12, indent: 20, endIndent: 20),
          const SizedBox(height: 8),
          _NavItem(icon: Icons.person_rounded,         label: 'Account',    route: '/account', index: 5, selected: selectedIndex == 5, expanded: expanded),
          _NavItem(icon: Icons.credit_card_rounded,    label: 'Billing',    route: '/account/pricing', index: 6, selected: selectedIndex == 6, expanded: expanded),
          _NavItem(icon: Icons.help_outline_rounded,   label: 'Support',    route: '/support', index: 7, selected: selectedIndex == 7, expanded: expanded),
          const Spacer(),
          // Collapse toggle
          InkWell(
            onTap: onToggle,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(expanded ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: Colors.white38, size: 20),
                  if (expanded) ...[
                    const SizedBox(width: 12),
                    const Text('Collapse', style: TextStyle(color: Colors.white38, fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String route;
  final int index;
  final bool selected;
  final bool expanded;
  const _NavItem({required this.icon, required this.label, required this.route, required this.index, required this.selected, required this.expanded});

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => Navigator.pushReplacementNamed(context, widget.route),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          padding: EdgeInsets.symmetric(horizontal: widget.expanded ? 14 : 12, vertical: 12),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.primaryBlue.withValues(alpha: 0.15)
                : _hovered ? Colors.white.withValues(alpha: 0.04) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: widget.selected
                ? Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: widget.selected ? AppColors.primaryBlue : Colors.white38, size: 20),
              if (widget.expanded) ...[
                const SizedBox(width: 12),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.selected ? AppColors.primaryBlue : Colors.white60,
                    fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final vpn = Provider.of<VPNProvider>(context);
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E1A),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          // Status pill
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: vpn.isConnected ? AppColors.success.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: vpn.isConnected ? AppColors.success.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: vpn.isConnected ? AppColors.success : Colors.white30)),
                const SizedBox(width: 8),
                Text(
                  vpn.isConnected ? 'Protected • ${vpn.currentServer}' : 'Not Protected',
                  style: TextStyle(color: vpn.isConnected ? AppColors.success : Colors.white38, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Quick actions
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded, color: Colors.white38),
            onPressed: () {},
            mouseCursor: SystemMouseCursors.click,
          ),
          const SizedBox(width: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/account'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.person_rounded, color: Colors.white60, size: 16),
                    SizedBox(width: 8),
                    Text('My Account', style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600)),
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
