part of 'main.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  int _reportReloadToken = 0;

  // 하단 탭을 전환합니다. 리포트 탭을 열 때는 새 key를 주어 저장된 최신 기록을 다시 읽습니다.
  void _changeTab(int index) {
    setState(() {
      _selectedIndex = index;
      if (index == 2) {
        _reportReloadToken++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // IndexedStack은 탭을 바꿔도 각 화면의 스크롤·입력 상태를 유지합니다.
    final pages = [
      const DailyNutritionPage(),
      const ProfilePage(),
      ReportPage(key: ValueKey(_reportReloadToken)),
    ];
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: _BottomNavigation(
        selectedIndex: _selectedIndex,
        onChanged: _changeTab,
      ),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation(
      {required this.selectedIndex, required this.onChanged});
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onChanged,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: '홈'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '내 정보'),
          NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: '리포트'),
        ],
      );
}
