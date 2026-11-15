/// A small holder for one captured photo of a banknote.
///
/// Created after the camera captures a side and passed to the verification
/// use case.
library;

/// One captured side handed to the verification pipeline.
class NoteImageInput {
  const NoteImageInput({required this.path});

  /// File path of the saved photo on the phone.
  final String path;
}
