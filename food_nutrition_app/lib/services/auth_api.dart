part of '../main.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.displayName,
    required this.onboardingCompleted,
  });
  final String id;
  final String displayName;
  final bool onboardingCompleted;

  AuthUser copyWith({bool? onboardingCompleted}) => AuthUser(
      id: id,
      displayName: displayName,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted);

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'].toString(),
        displayName: json['display_name'] as String? ?? 'Food Lens 사용자',
        onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
      );
}

// 식사 데이터와 분리해 로그인 세션 토큰만 기기 보안 저장소에 보관합니다.
class SessionStore {
  SessionStore._();
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'food_lens_access_token';

  static Future<void> save(String token) =>
      _storage.write(key: _tokenKey, value: token);
  static Future<String?> read() => _storage.read(key: _tokenKey);
  static Future<void> clear() => _storage.delete(key: _tokenKey);
  static Future<Map<String, String>> headers() async {
    final token = await read();
    return token == null ? {} : {'Authorization': 'Bearer $token'};
  }
}

class AuthApi {
  AuthApi._();

  static const _serverClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '908444813761-usju1vdrhk4oh05tpvra6pjs2ccb5ac2.apps.googleusercontent.com',
  );
  static const _kakaoNativeAppKey = String.fromEnvironment(
    'KAKAO_NATIVE_APP_KEY',
    defaultValue: 'fbb57845af2701c630ec17dc8fa3f2ab',
  );

  static final _google = GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId: _serverClientId,
  );

  static Future<AuthUser> _exchangeToken(
    String provider,
    Map<String, String> payload,
  ) async {
    final response = await http
        .post(
          Uri.parse('${FoodDataApi.baseUrl}/auth/$provider'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw Exception('$provider 로그인 서버 확인에 실패했습니다. (${response.statusCode})');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    await SessionStore.save(data['access_token'] as String);
    return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  static Future<AuthUser> signInWithGoogle() async {
    final account = await _google.signIn();
    if (account == null) throw Exception('Google 로그인이 취소되었습니다.');
    final authentication = await account.authentication;
    final idToken = authentication.idToken;
    if (idToken == null) throw Exception('Google ID 토큰을 받지 못했습니다.');
    return _exchangeToken('google', {'id_token': idToken});
  }

  static Future<AuthUser> signInWithKakao() async {
    if (_kakaoNativeAppKey.isEmpty) {
      throw Exception('카카오 네이티브 앱 키가 설정되지 않았습니다.');
    }
    final token = await (await kakao.isKakaoTalkInstalled()
        ? kakao.UserApi.instance.loginWithKakaoTalk()
        : kakao.UserApi.instance.loginWithKakaoAccount());
    return _exchangeToken('kakao', {'access_token': token.accessToken});
  }

  static Future<AuthUser?> restore() async {
    final token = await SessionStore.read();
    if (token == null) return null;
    final response = await http
        .get(Uri.parse('${FoodDataApi.baseUrl}/auth/me'),
            headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      await SessionStore.clear();
      return null;
    }
    return AuthUser.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<void> deleteAccount() async {
    final response = await http
        .delete(
          Uri.parse('${FoodDataApi.baseUrl}/auth/account'),
          headers: await SessionStore.headers(),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('회원 탈퇴 처리에 실패했습니다. (${response.statusCode})');
    }
  }

  static Future<void> signOut() async {
    await _google.signOut();
    try {
      await kakao.UserApi.instance.logout();
    } catch (_) {
      // No Kakao session is normal for Google-only users.
    }
    await SessionStore.clear();
  }
}