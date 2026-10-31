enum VerificationErrorKind {
  noConnection,
  timeout,
  server,
  badResponse,
  cancelled,
  unknown,
}

/// Domain-level error raised by any [CurrencyVerificationRepository].
class VerificationException implements Exception {
  const VerificationException(this.kind, this.message, {this.statusCode});

  final VerificationErrorKind kind;
  final String message;
  final int? statusCode;

  String get title => switch (kind) {
        VerificationErrorKind.noConnection => 'NO CONNECTION',
        VerificationErrorKind.timeout => 'REQUEST TIMED OUT',
        VerificationErrorKind.server => 'SERVER ERROR',
        VerificationErrorKind.badResponse => 'INVALID RESPONSE',
        VerificationErrorKind.cancelled => 'CANCELLED',
        VerificationErrorKind.unknown => 'UNEXPECTED ERROR',
      };

  @override
  String toString() => 'VerificationException($kind, $statusCode): $message';
}
