part of '../main.dart';

// PostgreSQL????ν븯???ъ슜???좎껜 ?뺣낫 紐⑤뜽?낅땲??
class UserProfile {
  const UserProfile({this.heightCm, this.weightKg, this.targetWeightKg});
  final double? heightCm;
  final double? weightKg;
  final double? targetWeightKg;

  // 媛앹껜瑜?濡쒖뺄 ??μ냼???ｌ쓣 ???덈뒗 JSON ?뺥깭濡?蹂?섑빀?덈떎.
  Map<String, dynamic> toJson() => {
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'target_weight_kg': targetWeightKg
      };
  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        heightCm: (json['height_cm'] as num?)?.toDouble(),
        weightKg: (json['weight_kg'] as num?)?.toDouble(),
        targetWeightKg: (json['target_weight_kg'] as num?)?.toDouble(),
      );
}

class WeightRecord {
  const WeightRecord({required this.date, required this.weightKg});
  final DateTime date;
  final double weightKg;

  // 媛앹껜瑜?濡쒖뺄 ??μ냼???ｌ쓣 ???덈뒗 JSON ?뺥깭濡?蹂?섑빀?덈떎.
  Map<String, dynamic> toJson() =>
      {'date': date.toIso8601String(), 'weight_kg': weightKg};
  factory WeightRecord.fromJson(Map<String, dynamic> json) => WeightRecord(
        date: DateTime.parse(json['date'] as String),
        weightKg: (json['weight_kg'] as num).toDouble(),
      );
}

// ?ъ쭊 ???μ쓽 AI 遺꾩꽍 寃곌낵瑜??대뒓 ?좎쭨쨌?앹궗??湲곕줉?덈뒗吏 ?④퍡 蹂닿??⑸땲??
class MealRecord {
  const MealRecord(
      {required this.id,
      required this.meal,
      required this.createdAt,
      required this.imagePath,
      required this.detection});
  final String id;
  final MealType meal;
  final DateTime createdAt;
  final String imagePath;
  final FoodDetection detection;

  // 媛앹껜瑜?濡쒖뺄 ??μ냼???ｌ쓣 ???덈뒗 JSON ?뺥깭濡?蹂?섑빀?덈떎.
  Map<String, dynamic> toJson() => {
        'id': id,
        'meal': meal.name,
        'created_at': createdAt.toIso8601String(),
        'image_path': imagePath,
        'detection': detection.toJson(),
      };

  factory MealRecord.fromJson(Map<String, dynamic> json) => MealRecord(
        id: json['id'] as String,
        meal: MealType.values.byName(json['meal'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        imagePath: json['image_path'] as String? ?? '',
        detection:
            FoodDetection.fromJson(json['detection'] as Map<String, dynamic>),
      );
}

// FastAPI /predict ?묐떟???뚯떇 ??嫄댁쓣 ?깆뿉???곌린 ?쎄쾶 蹂?섑븳 紐⑤뜽?낅땲??
class FoodDetection {
  const FoodDetection(
      {required this.foodCode,
      required this.foodName,
      required this.confidence,
      required this.servingGrams,
      required this.nutrition});
  final String foodCode;
  final String? foodName;
  final double confidence;
  final double? servingGrams;
  final Nutrition nutrition;

  // ?곸뼇 ?뺣낫 ?꾨씫 ??0?쇰줈 怨꾩궛?섏뿬 ?⑷퀎 ?붾㈃??以묐떒?섏? ?딅룄濡??⑸땲??
  double get energyKcal => nutrition.energyKcal ?? 0;
  double get carbohydrateG => nutrition.carbohydrateG ?? 0;
  double get proteinG => nutrition.proteinG ?? 0;
  double get fatG => nutrition.fatG ?? 0;
  double get sodiumMg => nutrition.sodiumMg ?? 0;

  // ?뚯떇紐?寃?됀룹쭅???깅줉 ?붾㈃?먯꽌 留뚮뱺 濡쒖뺄 ?뚯떇 湲곕줉?낅땲?? AI ?먯? 寃곌낵? ?숈씪???뺤떇?쇰줈 ??ν빀?덈떎.
  factory FoodDetection.manual({
    required String foodName,
    required double servingGrams,
    required double calories,
    required double protein,
    required double fat,
    required double sodium,
  }) =>
      FoodDetection(
        foodCode: 'manual_${DateTime.now().microsecondsSinceEpoch}',
        foodName: foodName,
        confidence: 1,
        servingGrams: servingGrams,
        nutrition: Nutrition(
          energyKcal: calories,
          proteinG: protein,
          fatG: fat,
          sodiumMg: sodium,
        ),
      );
  factory FoodDetection.fromJson(Map<String, dynamic> json) => FoodDetection(
        foodCode: json['food_code'] as String,
        foodName: json['food_name'] as String?,
        confidence: (json['confidence'] as num).toDouble(),
        servingGrams: (json['serving_grams'] as num?)?.toDouble(),
        nutrition: Nutrition.fromJson(
            json['nutrition_per_serving'] as Map<String, dynamic>?),
      );

  // 媛앹껜瑜?濡쒖뺄 ??μ냼???ｌ쓣 ???덈뒗 JSON ?뺥깭濡?蹂?섑빀?덈떎.
  Map<String, dynamic> toJson() => {
        'food_code': foodCode,
        'food_name': foodName,
        'confidence': confidence,
        'serving_grams': servingGrams,
        'nutrition_per_serving': nutrition.toJson(),
      };
}

// ?쒕쾭媛 諛섑솚??1???쒓났??湲곗? ?곸뼇 ?깅텇?낅땲??
class Nutrition {
  const Nutrition(
      {this.energyKcal,
      this.carbohydrateG,
      this.proteinG,
      this.fatG,
      this.sodiumMg});
  final double? energyKcal;
  final double? carbohydrateG;
  final double? proteinG;
  final double? fatG;
  final double? sodiumMg;

  factory Nutrition.fromJson(Map<String, dynamic>? json) => Nutrition(
        energyKcal: (json?['energy_kcal'] as num?)?.toDouble(),
        carbohydrateG: (json?['carbohydrate_g'] as num?)?.toDouble(),
        proteinG: (json?['protein_g'] as num?)?.toDouble(),
        fatG: (json?['fat_g'] as num?)?.toDouble(),
        sodiumMg: (json?['sodium_mg'] as num?)?.toDouble(),
      );

  // 媛앹껜瑜?濡쒖뺄 ??μ냼???ｌ쓣 ???덈뒗 JSON ?뺥깭濡?蹂?섑빀?덈떎.
  Map<String, dynamic> toJson() => {
        'energy_kcal': energyKcal,
        'carbohydrate_g': carbohydrateG,
        'protein_g': proteinG,
        'fat_g': fatG,
        'sodium_mg': sodiumMg,
      };
}

/// 사용자가 설정하는 기본 일일 영양 목표입니다.
class NutritionTargets {
  const NutritionTargets({
    required this.calories,
    required this.carbs,
    required this.protein,
    required this.fat,
  });
  const NutritionTargets.defaults()
      : calories = 2200,
        carbs = 330,
        protein = 65,
        fat = 70;

  final double calories;
  final double carbs;
  final double protein;
  final double fat;
}
