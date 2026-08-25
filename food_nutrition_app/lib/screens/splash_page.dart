part of '../main.dart';

/// 앱 시작 시 로고와 로딩 효과를 보여준 뒤 로그인 상태 확인 화면으로 이동합니다.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _logoScale = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _fadeIn = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );
    _openApp();
  }

  /// 짧은 시작 애니메이션 뒤 기존 AuthGate로 전환합니다.
  Future<void> _openApp() async {
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, __) => const AuthGate(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fadeIn,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale: _logoScale,
                    child: Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        color: AppColors.teal,
                        borderRadius: BorderRadius.circular(34),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33168B88),
                            blurRadius: 22,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.restaurant_menu_rounded,
                        color: Colors.white,
                        size: 58,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Food Lens',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppColors.darkTeal,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '음식 사진으로 영양을 확인하세요',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 40),
                  const SizedBox(
                    width: 116,
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      borderRadius: BorderRadius.all(Radius.circular(20)),
                      color: AppColors.teal,
                      backgroundColor: Color(0xFFE2ECE9),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
