/// Helper that creates the HTTP client (Dio) used for network calls.
///
/// Part of the shared "core" code. It sets timeouts and headers in one place.
library;

import 'package:dio/dio.dart';

/// Builds a [Dio] instance tuned for multipart image uploads.
///
/// [baseUrl] is the server address that request paths are added to.
Dio buildDioClient({required String baseUrl}) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      // Give up if the server cannot be reached within 10 seconds.
      connectTimeout: const Duration(seconds: 10),
      // Uploading two full-resolution JPEGs on mobile data can be slow.
      sendTimeout: const Duration(seconds: 45),
      // Max wait for the server's reply (it may need time to analyse images).
      receiveTimeout: const Duration(seconds: 60),
      // Replies are read as JSON.
      responseType: ResponseType.json,
      headers: {'Accept': 'application/json'},
    ),
  );
}
