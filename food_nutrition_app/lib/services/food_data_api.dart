part of '../main.dart';

// PostgreSQL에 저장된 앱 데이터를 FastAPI를 통해 읽고 씁니다.
class FoodDataApi {
  FoodDataApi._();
  static const _baseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8000');
  static Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_baseUrl$path').replace(queryParameters: query);
  static Future<Map<String, dynamic>> _get(String path,
      [Map<String, String>? query]) async {
    final r =
        await http.get(_uri(path, query)).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('DB 조회 오류 (${r.statusCode})');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> _getList(String path,
      [Map<String, String>? query]) async {
    final r =
        await http.get(_uri(path, query)).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('DB 조회 오류 (${r.statusCode})');
    return jsonDecode(r.body) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> _write(
      String method, String path, Map<String, dynamic> body) async {
    final r = http.Request(method, _uri(path))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);
    final streamed = await r.send().timeout(const Duration(seconds: 20));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('DB 저장 오류 (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<UserProfile> profile() async {
    final v = await _get('/data/profile');
    return UserProfile(
        heightCm: (v['height_cm'] as num?)?.toDouble(),
        weightKg: (v['weight_kg'] as num?)?.toDouble(),
        targetWeightKg: (v['target_weight_kg'] as num?)?.toDouble());
  }

  static Future<void> saveProfile(UserProfile p) async =>
      _write('PUT', '/data/profile', p.toJson());
  static Future<NutritionTargets> targets([DateTime? day]) async {
    final v = await _get(
        '/data/targets', day == null ? null : {'target_date': _date(day)});
    return v.isEmpty
        ? const NutritionTargets.defaults()
        : NutritionTargets(
            calories: (v['calories_kcal'] as num).toDouble(),
            carbs: (v['carbohydrates_g'] as num).toDouble(),
            protein: (v['protein_g'] as num).toDouble(),
            fat: (v['fat_g'] as num).toDouble());
  }

  static Future<void> saveTargets(NutritionTargets t, {DateTime? day}) async =>
      _write('PUT', '/data/targets', {
        'calories_kcal': t.calories,
        'carbohydrates_g': t.carbs,
        'protein_g': t.protein,
        'fat_g': t.fat,
        'target_date': day == null ? null : _date(day)
      });
  static Future<List<WeightRecord>> weights() async =>
      (await _getList('/data/weights'))
          .map((v) => WeightRecord(
              date: DateTime.parse(v['recorded_month'] as String),
              weightKg: (v['weight_kg'] as num).toDouble()))
          .toList();
  static Future<void> saveWeight(WeightRecord r) async => _write(
      'PUT',
      '/data/weights',
      {'recorded_month': _date(r.date), 'weight_kg': r.weightKg});
  static Future<List<Map<String, dynamic>>> foods(String query,
          {bool mineOnly = false}) async =>
      (await _getList(
              '/data/foods', {'q': query, 'mine_only': mineOnly.toString()}))
          .cast<Map<String, dynamic>>();
  static Future<Map<String, dynamic>> createFood(Map<String, dynamic> food) =>
      _write('POST', '/data/foods', food);
  static Future<List<MealRecord>> meals(DateTime from, DateTime to) async =>
      (await _getList(
              '/data/meals', {'from_date': _date(from), 'to_date': _date(to)}))
          .map((v) => MealRecord(
              id: v['id'].toString(),
              meal: MealType.values.byName(v['meal_type'] as String),
              createdAt: DateTime.now(),
              imagePath: v['image_url'] as String? ?? '',
              detection: FoodDetection.manual(
                  foodName: v['food_name'] as String,
                  servingGrams: (v['serving_grams'] as num?)?.toDouble() ?? 0,
                  calories: (v['calories_kcal'] as num).toDouble(),
                  protein: (v['protein_g'] as num).toDouble(),
                  fat: (v['fat_g'] as num).toDouble(),
                  sodium: (v['sodium_mg'] as num).toDouble())))
          .toList();
  static Future<Map<DateTime, List<MealRecord>>> mealsByDate(
      DateTime from, DateTime to) async {
    final raw = await _getList(
        '/data/meals', {'from_date': _date(from), 'to_date': _date(to)});
    final result = <DateTime, List<MealRecord>>{};
    for (final item in raw) {
      final v = item as Map<String, dynamic>;
      final date = DateTime.parse(v['meal_date'] as String);
      final record = MealRecord(
          id: v['id'].toString(),
          meal: MealType.values.byName(v['meal_type'] as String),
          createdAt: DateTime.now(),
          imagePath: v['image_url'] as String? ?? '',
          detection: FoodDetection.manual(
              foodName: v['food_name'] as String,
              servingGrams: (v['serving_grams'] as num?)?.toDouble() ?? 0,
              calories: (v['calories_kcal'] as num).toDouble(),
              protein: (v['protein_g'] as num).toDouble(),
              fat: (v['fat_g'] as num).toDouble(),
              sodium: (v['sodium_mg'] as num).toDouble()));
      result
          .putIfAbsent(DateTime(date.year, date.month, date.day), () => [])
          .add(record);
    }
    return result;
  }

  static Future<MealRecord> addMeal(DateTime day, MealRecord r,
      {String source = 'ai'}) async {
    final v = await _write('POST', '/data/meals', {
      'meal_date': _date(day),
      'meal_type': r.meal.name,
      'food': {
        'food_code': r.detection.foodCode,
        'food_name': r.detection.foodName,
        'source': source,
        'image_url': r.imagePath.isEmpty ? null : r.imagePath,
        'ai_confidence': r.detection.confidence,
        'serving_grams': r.detection.servingGrams,
        'calories_kcal': r.detection.energyKcal,
        'protein_g': r.detection.proteinG,
        'fat_g': r.detection.fatG,
        'sodium_mg': r.detection.sodiumMg
      }
    });
    return MealRecord(
        id: v['id'].toString(),
        meal: r.meal,
        createdAt: r.createdAt,
        imagePath: r.imagePath,
        detection: r.detection);
  }

  static Future<void> deleteMeal(String id) async {
    final r = await http.delete(_uri('/data/meal-foods/$id'));
    if (r.statusCode != 200) throw Exception('DB 삭제 오류');
  }
}
