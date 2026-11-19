import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../core/network/verification_exception.dart';
import '../../domain/note_image_input.dart';
import '../../domain/currency_verification_repository.dart';
import '../models/note_analysis_model.dart';

/// SERVER-BASED VERIFICATION (UNUSED ALTERNATIVE)
///
/// PURPOSE
/// An older/alternative way to analyze a note: send both photos to a remote
/// server and let the server return the evidence. THE APP DOES NOT USE THIS
/// CLASS NOW. The real pipeline runs on the phone, in
/// OnDeviceCurrencyVerificationRepository. This file is kept because it
/// implements the same [CurrencyVerificationRepository] interface, so the
/// two can be swapped.
///
/// HOW IT WOULD FIT
///   photos -> POST to the server -> server JSON -> [NoteAnalysisModel]
///   -> VerificationEngine.evaluate() (same engine as on-device).
///
/// MAIN SECTIONS
///  1. analyzeBanknote: check the files exist, upload them, parse the JSON.
///  2. _map: turn network errors (Dio) into readable VerificationExceptions.
///
/// Uploads both sides to `POST /api/v1/verify` as multipart form data.
class ApiCurrencyVerificationRepository
    implements CurrencyVerificationRepository {
  /// [_dio] is the configured HTTP client (base URL, timeouts).
  ApiCurrencyVerificationRepository(this._dio);

  final Dio _dio;

  /// Server route that receives the two images.
  static const String verifyPath = '/api/v1/verify';

  /// Label stored on the result to show it came from the server.
  @override
  String get sourceLabel => 'api';

  /// Sends the front and back photos to the server and returns the
  /// evidence it sends back.
  /// Steps: 1) make sure both files still exist, 2) upload as multipart
  /// form fields `front_image` and `back_image`, 3) read the JSON, which may
  /// be bare or wrapped in an `analysis` key, 4) convert errors to
  /// [VerificationException].
  @override
  Future<NoteAnalysisModel> analyzeBanknote({
    required NoteImageInput front,
    required NoteImageInput back,
  }) async {
    final frontImagePath = front.path;
    final backImagePath = back.path;
    for (final p in [frontImagePath, backImagePath]) {
      if (!File(p).existsSync()) {
        throw VerificationException(
          VerificationErrorKind.unknown,
          'Captured image is no longer available. Please rescan.',
        );
      }
    }

    try {
      final form = FormData.fromMap({
        'front_image': await MultipartFile.fromFile(
          frontImagePath,
          filename: 'front.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
        'back_image': await MultipartFile.fromFile(
          backImagePath,
          filename: 'back.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });

      final response = await _dio.post<Object?>(verifyPath, data: form);
      final body = response.data;
      if (body is! Map) {
        throw const VerificationException(
          VerificationErrorKind.badResponse,
          'Server returned an unexpected payload.',
        );
      }
      // Accept either a bare analysis or one wrapped in {"analysis": {...}}.
      final json = body['analysis'] is Map
          ? (body['analysis'] as Map).cast<String, dynamic>()
          : body.cast<String, dynamic>();
      return NoteAnalysisModel.fromJson(json);
    } on DioException catch (e) {
      throw _map(e);
    } on VerificationException {
      rethrow;
    } on Object catch (e) {
      // Type errors from malformed JSON land here.
      throw VerificationException(
        VerificationErrorKind.badResponse,
        'Could not parse verification response: $e',
      );
    }
  }

  /// Converts a network error into a [VerificationException] with a kind
  /// (timeout, no connection, cancelled, server error, unknown) and a
  /// message the user can read.
  VerificationException _map(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const VerificationException(
          VerificationErrorKind.timeout,
          'The verification server took too long to respond.',
        );
      case DioExceptionType.connectionError:
        return const VerificationException(
          VerificationErrorKind.noConnection,
          'Could not reach the verification server. Check the network and '
          'the server URL.',
        );
      case DioExceptionType.cancel:
        return const VerificationException(
          VerificationErrorKind.cancelled,
          'Verification was cancelled.',
        );
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        final detail = e.response?.data is Map
            ? (e.response!.data as Map)['detail']?.toString()
            : null;
        return VerificationException(
          VerificationErrorKind.server,
          detail ?? 'Server responded with status $code.',
          statusCode: code,
        );
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        if (e.error is SocketException) {
          return const VerificationException(
            VerificationErrorKind.noConnection,
            'No network connection.',
          );
        }
        return VerificationException(
          VerificationErrorKind.unknown,
          e.message ?? 'Unexpected network error.',
        );
    }
  }
}
