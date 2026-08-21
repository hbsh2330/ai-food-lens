part of '../main.dart';

/// Restores the Food Lens session and shows onboarding for first-time users.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AuthUser? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final user = await AuthApi.restore();
    if (!mounted) return;
    setState(() {
      _user = user;
      _loading = false;
    });
  }

  Future<void> _signInWithGoogle() async {
    final user = await AuthApi.signInWithGoogle();
    if (mounted) setState(() => _user = user);
  }

  Future<void> _signInWithKakao() async {
    final user = await AuthApi.signInWithKakao();
    if (mounted) setState(() => _user = user);
  }

  /// 현재 로그인 공급자의 세션과 앱 JWT를 정리한 뒤 로그인 화면으로 전환합니다.
  Future<void> _signOut() async {
    await AuthApi.signOut();
    if (mounted) setState(() => _user = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_user == null) {
      return LoginPage(
        onGoogleSignIn: _signInWithGoogle,
        onKakaoSignIn: _signInWithKakao,
      );
    }
    if (!_user!.onboardingCompleted) {
      return ProfileSetupPage(
        displayName: _user!.displayName,
        onCompleted: () => setState(
          () => _user = _user!.copyWith(onboardingCompleted: true),
        ),
      );
    }
    return AppShell(onSignOut: _signOut);
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onGoogleSignIn,
    required this.onKakaoSignIn,
  });

  final Future<void> Function() onGoogleSignIn;
  final Future<void> Function() onKakaoSignIn;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _submitting = false;
  String? _error;

  Future<void> _login(Future<void> Function() signIn) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await signIn();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),
                const CircleAvatar(
                  radius: 44,
                  backgroundColor: Color(0xFFE4F4F1),
                  child: Icon(
                    Icons.restaurant_menu_rounded,
                    size: 48,
                    color: AppColors.teal,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Food Lens',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                const Text(
                  '사진으로 기록하는 나만의 식사·영양 관리',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 16),
                ),
                const Spacer(flex: 2),
                if (_error != null) ...[
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: _submitting
                      ? null
                      : () => _login(widget.onGoogleSignIn),
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.g_mobiledata_rounded, size: 30),
                  label: const Text('Google로 계속하기'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    foregroundColor: Colors.black87,
                    side: const BorderSide(color: Color(0xFFDDE1E0)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _submitting
                      ? null
                      : () => _login(widget.onKakaoSignIn),
                  icon: const Icon(Icons.chat_bubble_rounded, size: 20),
                  label: const Text('카카오로 계속하기'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    foregroundColor: const Color(0xFF191919),
                    backgroundColor: const Color(0xFFFEE500),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '로그인하면 식사 기록과 목표가 계정별로 안전하게 저장됩니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      );
}
