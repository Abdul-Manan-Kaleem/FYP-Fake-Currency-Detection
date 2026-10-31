import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../core/network/verification_exception.dart';
import '../../domain/note_image_input.dart';
import '../../domain/currency_verification_repository.dart';
import '../models/note_analysis_model.dart';

/// Uploads both sides to `POST /api/v1/verify` as multipart form data.
class ApiCurrencyVerificationRepository
    implements CurrencyVerificationRepository {
  ApiCurrencyVerificationRepository(this._dio);

  final Dio _dio;

  static const String verifyPath = '/api/v1/verify';

  @override
  String get sourceLabel => 'api';

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
