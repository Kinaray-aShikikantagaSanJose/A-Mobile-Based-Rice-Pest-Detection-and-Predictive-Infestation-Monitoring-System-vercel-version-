import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:myapp/utils/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('discovers and verifies a running local Palay Patrol API', () async {
    if (Platform.environment['PALAY_API_INTEGRATION_TEST'] != '1') {
      markTestSkipped('Set PALAY_API_INTEGRATION_TEST=1 with the API running on port 8000.');
      return;
    }
    SharedPreferences.setMockInitialValues({});
    ApiConfig.invalidate();

    await ApiConfig.ensureReachable().timeout(const Duration(seconds: 45));

    expect(ApiConfig.connected.value, isTrue);
    final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/openapi.json'));
    final spec = jsonDecode(response.body) as Map<String, dynamic>;
    expect(response.statusCode, 200);
    expect((spec['info'] as Map<String, dynamic>)['title'], 'Crop Protection API');
    expect(spec['paths'], contains('/analytics/trends/prediction'));
  });
}
