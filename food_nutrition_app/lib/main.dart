import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kakao_flutter_sdk_common/kakao_flutter_sdk_common.dart' as kakao_common;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;

part 'app_shell.dart';
part 'core/app_theme.dart';
part 'models/food_models.dart';
part 'services/food_api.dart';
part 'services/food_data_api.dart';
part 'services/auth_api.dart';
part 'screens/daily_nutrition_page.dart';
part 'screens/profile_page.dart';
part 'screens/report_page.dart';
part 'screens/nutrition_detail_page.dart';
part 'screens/food_add_page.dart';
part 'screens/login_page.dart';
part 'screens/profile_setup_page.dart';
part 'screens/my_foods_page.dart';
part 'screens/legal_document_page.dart';
part 'screens/splash_page.dart';

// 앱의 시작점: 최상위 위젯을 실행합니다.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const kakaoNativeAppKey = String.fromEnvironment(
    'KAKAO_NATIVE_APP_KEY',
    defaultValue: 'fbb57845af2701c630ec17dc8fa3f2ab',
  );
  if (kakaoNativeAppKey.isNotEmpty) {
    await kakao_common.KakaoSdk.init(nativeAppKey: kakaoNativeAppKey);
  }
  runApp(const FoodNutritionApp());
}

// 앱 전체의 언어, 테마, 첫 화면을 설정하는 최상위 위젯입니다.
class FoodNutritionApp extends StatelessWidget {
  const FoodNutritionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Food Lens',
      locale: const Locale('ko', 'KR'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ko', 'KR')],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.teal),
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'sans',
      ),
      home: const SplashPage(),
    );
  }
}
