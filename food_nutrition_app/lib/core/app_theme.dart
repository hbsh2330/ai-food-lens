part of '../main.dart';

// 앱 전체에서 재사용하는 색상 팔레트입니다.
class AppColors {
  static const background = Color(0xFFF6F7F3);
  static const teal = Color(0xFF168B88);
  static const darkTeal = Color(0xFF126A6B);
  static const orange = Color(0xFFFFA11A);
  static const card = Colors.white;
  static const muted = Color(0xFF78817F);
}

// 식사 구분의 내부 값입니다. 저장 시에는 enum 이름, 화면에는 아래 확장 함수의 한글 라벨을 사용합니다.
enum MealType { breakfast, lunch, dinner }

extension MealTypeLabel on MealType {
  String get label => switch (this) {
        MealType.breakfast => '아침',
        MealType.lunch => '점심',
        MealType.dinner => '저녁',
      };

  IconData get icon => switch (this) {
        MealType.breakfast => Icons.wb_sunny_outlined,
        MealType.lunch => Icons.restaurant_outlined,
        MealType.dinner => Icons.nights_stay_outlined,
      };

  Color get color => switch (this) {
        MealType.breakfast => const Color(0xFFF5A623),
        MealType.lunch => const Color(0xFF45A26B),
        MealType.dinner => const Color(0xFF527AD5),
      };
}
