enum NoteSide {
  front,
  back;

  String get label => name.toUpperCase();
}

enum CaptureSource { documentScanner, camera, gallery }

class CapturedImage {
  const CapturedImage({
    required this.path,
    required this.side,
    required this.source,
    required this.capturedAt,
    this.denomination,
  });

  final String path;
  final NoteSide side;
  final CaptureSource source;
  final DateTime capturedAt;

  /// Denomination recognised right after capture (YOLO on the front,
  /// monument on the back), if confident.
  final int? denomination;
}

/// Steps of the guided two-sided capture flow.
enum CaptureStep { front, flip, back, review }

class CaptureState {
  const CaptureState({
    this.front,
    this.back,
    this.step = CaptureStep.front,
    this.busy = false,
    this.error,
    this.basicCameraSide,
    this.busyMessage,
    this.sideError,
  });

  final CapturedImage? front;
  final CapturedImage? back;
  final CaptureStep step;
  final bool busy;
  final String? error;

  /// Shown on the scanner HUD while busy (e.g. "checking side").
  final String? busyMessage;

  /// Wrong side scanned: shown as a pop-up, the photo is not kept.
  final SideError? sideError;

  /// Set when the ML Kit scanner failed for this side and the plain camera
  /// can be offered instead.
  final NoteSide? basicCameraSide;

  bool get isComplete => front != null && back != null;

  CapturedImage? imageFor(NoteSide side) =>
      side == NoteSide.front ? front : back;

  CaptureState copyWith({
    CapturedImage? front,
    CapturedImage? back,
    CaptureStep? step,
    bool? busy,
    String? error,
    NoteSide? basicCameraSide,
    String? busyMessage,
    SideError? sideError,
    bool clearError = false,
    bool clearBusyMessage = false,
  }) {
    return CaptureState(
      front: front ?? this.front,
      back: back ?? this.back,
      step: step ?? this.step,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      basicCameraSide:
          clearError ? null : (basicCameraSide ?? this.basicCameraSide),
      busyMessage: clearBusyMessage ? null : (busyMessage ?? this.busyMessage),
      sideError: clearError ? null : (sideError ?? this.sideError),
    );
  }
}

/// Wrong-side message, in Roman Urdu with an English line.
class SideError {
  const SideError({
    required this.urdu,
    required this.english,
    this.title = 'GALAT SIDE · WRONG SIDE',
    this.notBanknote = false,
  });

  final String urdu;
  final String english;

  /// Heading of the pop-up.
  final String title;

  /// True when the photograph shows no banknote at all (different icon and
  /// colour in the pop-up).
  final bool notBanknote;

  /// The photograph is not a banknote: shown right after the first photo, so
  /// the user is never asked for the back of something that is not a note.
  static const notABanknote = SideError(
    title: 'INVALID IMAGE · NOT A NOTE',
    notBanknote: true,
    urdu: 'Ye Pakistani note ki tasveer nahi hai. Poora note saaf roshni me, '
        'sadi surface par rakh kar dobara scan karen.',
    english: 'This is not an image of a Pakistani banknote, so it was not '
        'accepted. Place the whole note flat on a plain surface in good light '
        'and scan it again.',
  );

  static const backOnFront = SideError(
    urdu: 'Ye note ki back side hai! Barah-e-meherbani pehle front side '
        '(Quaid wali side) scan karen.',
    english: 'This is the BACK of the note. Please scan the FRONT '
        '(Quaid-e-Azam portrait side) first.',
  );

  static const frontOnBack = SideError(
    urdu: 'Ye front side hai, ab back side (Building wali side) scan karen.',
    english: 'This is the FRONT. Now scan the BACK (building side).',
  );

  /// The back shows another note's monument than the front's denomination.
  static SideError wrongNote({required int found, required int scanning}) =>
      SideError(
        urdu: 'Ye $found ka note hai, aap $scanning scan kar rahe hain.',
        english: 'This back belongs to a Rs $found note, but the front you '
            'scanned is Rs $scanning. Scan the back of the same note.',
      );

  static const sameSideTwice = SideError(
    urdu: 'Aap ne ye side pehle hi scan kar li hai. Ab back side '
        '(Building wali side) scan karen.',
    english: 'You already scanned this side. Now scan the BACK (building side).',
  );
}
