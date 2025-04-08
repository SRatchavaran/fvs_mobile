import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  final String baseUrl = "<YOUR_URL>";

  // ฟังก์ชัน POST
  Future<Map<String, dynamic>> personalVerify({
    required String imageBase64,
    required String pid,
  }) async {
    Map<String, String> headers = {
      "API-KEY": "<YOUR_KEY>",
      "Content-Type": "application/json"
    };
    final response = await http.post(
      Uri.parse('$baseUrl/$pid'),
      headers: headers,
      body: jsonEncode({"image": imageBase64}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to create post");
    }
  }
}
