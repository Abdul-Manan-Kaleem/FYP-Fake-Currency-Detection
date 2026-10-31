import 'package:dio/dio.dart';

/// Builds a [Dio] instance tuned for multipart image uploads.
Dio buildDioClient({required String baseUrl}) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      // Uploading two full-resolution JPEGs on mobile data can be slow.
      sendTimeout: const Duration(seconds: 45),
      receiveTimeout: const Duration(seconds: 60),
      responseType: ResponseType.json,
      headers: {'Accept': 'application/json'},
    ),
  );
}
