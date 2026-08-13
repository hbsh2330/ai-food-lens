part of '../main.dart';

class FoodApi {
  FoodApi._();

  // Android 에뮬레이터에서는 10.0.2.2가 개발 PC의 localhost를 가리킵니다.
  // 실제 기기·배포 환경에서는 --dart-define=API_BASE_URL=...으로 주소를 바꿉니다.
  static const _baseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8000');

  // 선택/촬영한 이미지를 multipart 형식으로 FastAPI /predict에 전송하고, 첫 번째 탐지 결과를 반환합니다.
  static Future<FoodDetection> predict(File image) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$_baseUrl/predict'))
          ..files.add(await http.MultipartFile.fromPath('file', image.path));
    final response = await request.send().timeout(const Duration(seconds: 45));
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      throw Exception('API 오류 (${response.statusCode}): $body');
    }

    final payload = jsonDecode(body) as Map<String, dynamic>;
    final detections = payload['detections'] as List<dynamic>;
    if (detections.isEmpty) {
      throw Exception('음식을 찾지 못했습니다. 음식이 더 크게 보이도록 다시 촬영해 주세요.');
    }
    return FoodDetection.fromJson(detections.first as Map<String, dynamic>);
  }
}
