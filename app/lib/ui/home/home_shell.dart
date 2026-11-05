import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';

import '../rooms/explorer_screen.dart';
import '../settings/settings_screen.dart';
import '../timetable/timetable_screen.dart';
import '../updates/updates_screen.dart';
import 'campus_home.dart';

/// Navigation callbacks shared with child screens (e.g. campus landmarks).
class ShellNav extends InheritedWidget {
  final void Function(int tab, {int? updatesTab}) go;
  const ShellNav({super.key, required this.go, required super.child});
  static ShellNav of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<ShellNav>()!;
  @override
  bool updateShouldNotify(ShellNav old) => false;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  final _updatesTab = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Focus sessions are wall-clock based; settle them when the app resumes.
    if (state == AppLifecycleState.resumed) context.read<AppState>().settleFocus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updatesTab.dispose();
    super.dispose();
  }

  void _go(int tab, {int? updatesTab}) {
    if (updatesTab != null) _updatesTab.value = updatesTab;
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    return ShellNav(
      go: _go,
      child: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            const CampusHome(),
            const TimetableScreen(),
            const ExplorerScreen(),
            UpdatesScreen(tabIndex: _updatesTab),
            const SettingsScreen(),
          ],
        ),
        bottomNavigationBar: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -4))],
          ),
          child: NavigationBar(
            height: 70,
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.park_outlined), selectedIcon: Icon(Icons.park_rounded), label: 'Campus'),
              NavigationDestination(
                icon: Icon(Icons.calendar_view_day_outlined),
                selectedIcon: Icon(Icons.calendar_view_day_rounded),
                label: 'Timetable',
              ),
              NavigationDestination(
                icon: Icon(Icons.meeting_room_outlined),
                selectedIcon: Icon(Icons.meeting_room_rounded),
                label: 'Rooms',
              ),
              NavigationDestination(icon: Icon(Icons.campaign_outlined), selectedIcon: Icon(Icons.campaign_rounded), label: 'Updates'),
              NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Me'),
            ],
          ),
        ),
      ),
    );
  }
}
