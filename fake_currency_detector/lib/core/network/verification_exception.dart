/// Error type used when checking a note over the network fails.
///
/// Holds a simple error category plus a readable message, so screens can
/// show a clear error title to the user.
library;

/// The different reasons a verification request can fail.
enum VerificationErrorKind {
  /// The phone has no working internet connection.
  noConnection,

  /// The server took too long to answer.
  timeout,

  /// The server replied with an error.
  server,

  /// The server's reply could not be understood.
  badResponse,

  /// The request was cancelled before it finished.
  cancelled,

  /// Any other failure.
  unknown,
}

/// Domain-level error raised by any [CurrencyVerificationRepository].
class VerificationException implements Exception {
  const VerificationException(this.kind, this.message, {this.statusCode});

  /// Which category of failure this is.
  final VerificationErrorKind kind;

  /// Human-readable detail about what went wrong.
  final String message;

  /// HTTP status code from the server, if there was one.
  final int? statusCode;

  /// Short upper-case heading for the error, chosen from [kind].
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
