import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:table_calendar/table_calendar.dart';

part 'app_shell.dart';
part 'core/app_theme.dart';
part 'models/food_models.dart';
part 'services/food_api.dart';
part 'services/food_data_api.dart';
part 'screens/daily_nutrition_page.dart';
part 'screens/profile_page.dart';
part 'screens/report_page.dart';
part 'screens/nutrition_detail_page.dart';
part 'screens/food_add_page.dart';

// 앱의 시작점: 최상위 위젯을 실행합니다.
void main() => runApp(const FoodNutritionApp());

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
      home: const AppShell(),
    );
  }
}
