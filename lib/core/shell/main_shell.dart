// lib/core/shell/main_shell.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart';


class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.child});
  final Widget child;

  static const _tabs = [
    (route: AppRoutes.chat,     icon: Icons.chat_bubble_outline,            label: 'حماده'),
    (route: AppRoutes.notes,    icon: Icons.note_outlined,                   label: 'ملاحظاتي'),
    (route: AppRoutes.finance,  icon: Icons.account_balance_wallet_outlined, label: 'حساباتي'),
    (route: AppRoutes.planner,  icon: Icons.check_box_outlined,              label: 'مهامي'),
    (route: AppRoutes.settings, icon: Icons.settings_outlined,               label: 'الإعدادات'),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    int idx = _tabs.indexWhere((t) => t.route == location);
    if (idx < 0) idx = 0;

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.06), width: 0.5),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: idx,
          onTap: (i) => context.go(_tabs[i].route),
          items: _tabs.map((t) => BottomNavigationBarItem(
            icon:  Icon(t.icon),
            label: t.label,
          )).toList(),
        ),
      ),
    );
  }
}
