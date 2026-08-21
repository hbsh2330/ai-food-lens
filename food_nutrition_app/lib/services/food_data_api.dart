part of '../main.dart';

// PostgreSQL 데이터를 로그인한 사용자 토큰과 함께 FastAPI에 요청합니다.
class FoodDataApi {
  FoodDataApi._();
  static const baseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8000');

  static Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  static Future<Map<String, String>> _headers() => SessionStore.headers();

  static Future<Map<String, dynamic>> _get(String path,
      [Map<String, String>? query]) async {
    final r = await http
        .get(_uri(path, query), headers: await _headers())
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('DB 조회 오류 (${r.statusCode})');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> _getList(String path,
      [Map<String, String>? query]) async {
    final r = await http
        .get(_uri(path, query), headers: await _headers())
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('DB 조회 오류 (${r.statusCode})');
    return jsonDecode(r.body) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> _write(
      String method, String path, Map<String, dynamic> body) async {
    final r = http.Request(method, _uri(path))
      ..headers.addAll(await _headers())
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

  static Future<UserProfile> profile() async =>
      UserProfile.fromJson(await _get('/data/profile'));

  static Future<void> saveProfile(UserProfile p) async =>
      _write('PUT', '/data/profile', p.toJson());

  // 첫 설정에서 서버가 계산한 개인별 기본 영양 목표를 함께 저장합니다.
  static Future<NutritionTargets> completeProfileSetup(
      Map<String, dynamic> setup) async {
    final v = await _write('PUT', '/data/profile/setup', setup);
    final targets = v['targets'] as Map<String, dynamic>;
    return NutritionTargets(
      calories: (targets['calories_kcal'] as num).toDouble(),
      carbs: (targets['carbohydrates_g'] as num).toDouble(),
      protein: (targets['protein_g'] as num).toDouble(),
      fat: (targets['fat_g'] as num).toDouble(),
    );
  }

  static Future<NutritionTargets> targets([DateTime? day]) async {
    final v = await _get(
        '/data/targets', day == null ? null : {'target_date': _date(day)});
    return v.isEmpty
        ? const NutritionTargets.defaults()
        : NutritionTargets(
            calories: (v['calories_kcal'] as num).toDouble(),
            carbs: (v['carbohydrates_g'] as num).toDouble(),
            protein: (v['protein_g'] as num).toDouble(),
            fat: (v['fat_g'] as num).toDouble(),
            keepCustomNutritionTargets: v['keep_custom_nutrition_targets'] as bool? ?? false);
  }

  static Future<void> saveTargets(NutritionTargets t, {DateTime? day, DateTime? effectiveFrom, bool? keepCustomNutritionTargets}) async =>
      _write('PUT', '/data/targets', {
        'calories_kcal': t.calories,
        'carbohydrates_g': t.carbs,
        'protein_g': t.protein,
        'fat_g': t.fat,
        'target_date': day == null ? null : _date(day),
        if (day == null && effectiveFrom != null) 'effective_from': _date(effectiveFrom),
        if (day == null && keepCustomNutritionTargets != null)
          'keep_custom_nutrition_targets': keepCustomNutritionTargets,
      });

  static Future<List<WeightRecord>> weights() async =>
      (await _getList('/data/weights'))
          .map((v) => WeightRecord(
              date: DateTime.parse(v['recorded_month'] as String),
              weightKg: (v['weight_kg'] as num).toDouble()))
          .toList();

  static Future<void> saveWeight(WeightRecord r) async => _write(
      'PUT', '/data/weights',
      {'recorded_month': _date(r.date), 'weight_kg': r.weightKg});

  static Future<List<Map<String, dynamic>>> foods(String query,
          {bool mineOnly = false}) async =>
      (await _getList(
              '/data/foods', {'q': query, 'mine_only': mineOnly.toString()}))
          .cast<Map<String, dynamic>>();

  static Future<Map<String, dynamic>> createFood(Map<String, dynamic> food) =>
      _write('POST', '/data/foods', food);

  static Future<List<Map<String, dynamic>>> myFoods() async =>
      (await _getList('/data/my-foods')).cast<Map<String, dynamic>>();

  static Future<Map<String, dynamic>> updateMyFood(
          String foodId, Map<String, dynamic> food) =>
      _write('PUT', '/data/foods/$foodId', food);

  static Future<void> deleteMyFood(String foodId) async {
    final response = await http
        .delete(_uri('/data/foods/$foodId'), headers: await _headers())
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Food delete error (${response.statusCode})');
    }
  }
  // 음식 사진은 먼저 업로드하고, 반환된 경로를 음식 데이터에 저장합니다.
  static Future<String> uploadFoodImage(File image) async {
    final request = http.MultipartRequest('POST', _uri('/data/food-images'))
      ..headers.addAll(await _headers())
      ..files.add(await http.MultipartFile.fromPath('file', image.path));
    final response = await request.send().timeout(const Duration(seconds: 30));
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('음식 사진 업로드 오류 (${response.statusCode})');
    }
    return (jsonDecode(body) as Map<String, dynamic>)['image_url'] as String;
  }

  // 서버가 준 상대 경로를 에뮬레이터/실기기에서 접근 가능한 전체 주소로 변환합니다.
  static String imageUrl(String path) =>
      path.startsWith('http') ? path : '$baseUrl$path';

  // Saves feedback only after the user selected the actual food and the meal was saved.
  static Future<String> saveAiFeedbackAfterMeal(
    File image, {
    FoodDetection? predicted,
    List<Map<String, dynamic>> candidates = const [],
  }) async {
    final request = http.MultipartRequest('POST', _uri('/data/ai-feedback'))
      ..headers.addAll(await _headers())
      ..fields['failure_reason'] =
          predicted == null ? 'invalid_food_code' : 'incorrect_prediction'
      ..fields['feedback_type'] =
          predicted == null ? 'unrecognized' : 'incorrect'
      ..fields['candidates_json'] = jsonEncode(candidates)
      ..files.add(await http.MultipartFile.fromPath('file', image.path));
    if (predicted != null) {
      request.fields['predicted_food_code'] = predicted.foodCode;
      request.fields['predicted_food_name'] = predicted.foodName ?? '';
      request.fields['predicted_confidence'] = predicted.confidence.toString();
    }
    final response = await request.send().timeout(const Duration(seconds: 30));
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('AI feedback save failed (${response.statusCode})');
    }
    return (jsonDecode(body) as Map<String, dynamic>)['id'].toString();
  }
  // Links the food selected in search to the saved failed-recognition image.
  static Future<void> completeAiFeedback(
      String feedbackId, FoodDetection corrected) async {
    await _write('PUT', '/data/ai-feedback/$feedbackId/correction', {
      'corrected_food_id': corrected.foodId,
      'corrected_food_name': corrected.foodName ?? '직접 등록 음식',
      'corrected_food_code': corrected.foodCode,
    });
  }

  static Future<List<MealRecord>> meals(DateTime from, DateTime to) async =>
      (await _getList(
              '/data/meals', {'from_date': _date(from), 'to_date': _date(to)}))
          .map((v) => _recordFromApi(v as Map<String, dynamic>))
          .toList();

  static MealRecord _recordFromApi(Map<String, dynamic> v) => MealRecord(
      id: v['id'].toString(),
      meal: MealType.values.byName(v['meal_type'] as String),
      createdAt: DateTime.now(),
      imagePath: v['image_url'] as String? ?? '',
      detection: FoodDetection.manual(
          foodName: v['food_name'] as String,
          servingGrams: (v['serving_grams'] as num?)?.toDouble() ?? 0,
          servingUnit: v['serving_unit'] as String? ?? 'grams',
          servingCount: (v['serving_count'] as num?)?.toDouble(),
          calories: (v['calories_kcal'] as num).toDouble(),
          carbohydrate: (v['carbohydrate_g'] as num?)?.toDouble() ?? 0,
          protein: (v['protein_g'] as num).toDouble(),
          fat: (v['fat_g'] as num).toDouble(),
          sodium: (v['sodium_mg'] as num).toDouble()));

  static Future<Map<DateTime, List<MealRecord>>> mealsByDate(
      DateTime from, DateTime to) async {
    final raw = await _getList(
        '/data/meals', {'from_date': _date(from), 'to_date': _date(to)});
    final result = <DateTime, List<MealRecord>>{};
    for (final item in raw) {
      final v = item as Map<String, dynamic>;
      final date = DateTime.parse(v['meal_date'] as String);
      result
          .putIfAbsent(DateTime(date.year, date.month, date.day), () => [])
          .add(_recordFromApi(v));
    }
    return result;
  }

  static Future<MealRecord> addMeal(DateTime day, MealRecord r,
      {String source = 'ai'}) async {
    final v = await _write('POST', '/data/meals', {
      'meal_date': _date(day),
      'meal_type': r.meal.name,
      'food': {
        'food_id': r.detection.foodId,
        'food_code': r.detection.foodCode,
        'food_name': r.detection.foodName,
        'source': source,
        'image_url': r.imagePath.isEmpty ? null : r.imagePath,
        'ai_confidence': r.detection.confidence,
        'serving_grams': r.detection.servingGrams,
        'serving_unit': r.detection.servingUnit,
        'serving_count': r.detection.servingCount,
        'calories_kcal': r.detection.energyKcal,
        'carbohydrate_g': r.detection.carbohydrateG,
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

  static Future<void> updateMeal(String id, FoodDetection food,
      {required String imagePath}) async {
    await _write('PUT', '/data/meal-foods/$id', {
      'food_name': food.foodName,
      'image_url': imagePath.isEmpty ? null : imagePath,
      'serving_grams': food.servingGrams,
      'serving_unit': food.servingUnit,
      'serving_count': food.servingCount,
      'calories_kcal': food.energyKcal,
      'carbohydrate_g': food.carbohydrateG,
      'protein_g': food.proteinG,
      'fat_g': food.fatG,
      'sodium_mg': food.sodiumMg,
    });
  }
  static Future<void> deleteMeal(String id) async {
    final r = await http.delete(_uri('/data/meal-foods/$id'),
        headers: await _headers());
    if (r.statusCode != 200) throw Exception('DB 삭제 오류');
  }
}