part of '../main.dart';

class FoodNotRecognizedException implements Exception {
  const FoodNotRecognizedException({this.candidates = const []});

  final List<Map<String, dynamic>> candidates;

  @override
  String toString() => 'AI could not recognize this food image.';
}

class FoodApi {
  FoodApi._();

  static const _baseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8000');

  static Future<FoodDetection> predict(File image) async {
    final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/predict'))
      ..headers.addAll(await SessionStore.headers())
      ..files.add(await http.MultipartFile.fromPath('file', image.path));
    final response = await request.send().timeout(const Duration(seconds: 45));
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      throw Exception('API error (${response.statusCode}): $body');
    }

    final payload = jsonDecode(body) as Map<String, dynamic>;
    final detections = payload['detections'] as List<dynamic>? ?? const [];
    final candidates = (payload['candidates'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    if (detections.isEmpty) {
      throw FoodNotRecognizedException(candidates: candidates);
    }

    final detection = FoodDetection.fromJson(
      detections.first as Map<String, dynamic>,
    );
    final name = detection.foodName?.trim();
    if (detection.foodCode == '00000000' ||
        name == null ||
        name.isEmpty ||
        name.toLowerCase() == 'none') {
      throw FoodNotRecognizedException(candidates: candidates);
    }
    return detection.copyWith(aiCandidates: candidates);
  }
}