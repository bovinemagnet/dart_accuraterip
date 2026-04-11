/// Immutable result models returned by the AccurateRip database.
///
/// Author: Paul Snow
/// Since: 0.0.1
library;

/// The decoded result of an AccurateRip database lookup for a disc.
///
/// A disc lookup may return data for multiple *pressings* of the
/// same disc. Entries for each pressing are concatenated into each
/// track's [AccurateRipTrackResult.entries] list, so a typical
/// verification flow iterates [tracks] and checks each track's
/// locally computed v1 and v2 CRCs against the entries.
class AccurateRipDiscResult {
  /// Create an [AccurateRipDiscResult] wrapping the given per-track
  /// results.
  const AccurateRipDiscResult({required this.tracks});

  /// Per-track results in ascending track-number order (1-based).
  final List<AccurateRipTrackResult> tracks;
}

/// AccurateRip data for a single track, aggregated across every
/// pressing present in the response.
class AccurateRipTrackResult {
  /// Create an [AccurateRipTrackResult].
  const AccurateRipTrackResult({
    required this.trackNumber,
    required this.entries,
  });

  /// The 1-based track number.
  final int trackNumber;

  /// One entry per pressing (submission) in the database. A
  /// verification succeeds when the locally computed v1 or v2 CRC
  /// matches any entry's [AccurateRipEntry.crc] — see
  /// [AccurateRipEntry.matches].
  final List<AccurateRipEntry> entries;
}

/// A single AccurateRip entry for one pressing of a track.
///
/// Each entry in a response carries exactly **one** primary CRC
/// ([crc]) plus a secondary offset-detection CRC ([frame450Crc]).
/// The server stores whatever CRC the submitting ripper sent —
/// older submissions stored the AccurateRip v1 CRC, newer
/// submissions stored the v2 CRC. Clients cannot tell which
/// version a given entry was submitted under, so they must try
/// both their locally computed v1 and v2 against [crc]. See
/// [matches] for the one-liner.
class AccurateRipEntry {
  /// Create an [AccurateRipEntry].
  const AccurateRipEntry({
    required this.confidence,
    required this.crc,
    required this.frame450Crc,
  });

  /// Number of independent submissions that reported this CRC.
  /// Higher values indicate greater confidence that the CRC
  /// represents a correct rip of this pressing.
  final int confidence;

  /// The single primary CRC the server stores for this pressing.
  ///
  /// This is the field the client compares against. It may hold
  /// either an AccurateRip v1 or an AccurateRip v2 value,
  /// depending on which era the submitting ripper was from. To
  /// verify a rip, compute BOTH [computeArV1] and [computeArV2]
  /// locally and check whether either equals [crc] — the
  /// convenience helper [matches] does this for you.
  final int crc;

  /// Secondary CRC computed over only the first 450 stereo frames
  /// of the track, used by some rippers (notably CUETools) to
  /// verify drive read-offset alignment. May be `0` for older
  /// pressings that predate this field.
  ///
  /// Consumers who only care about "is my rip bit-accurate" can
  /// safely ignore this field and rely on [matches] / [crc].
  final int frame450Crc;

  /// Returns `true` when either [computedV1] or [computedV2]
  /// equals [crc] — i.e. the rip matches this pressing.
  ///
  /// This is the canonical way to verify a ripped track against
  /// an AccurateRip database entry. Both CRCs must be supplied
  /// because the caller cannot tell in advance which AR version
  /// the pressing was submitted under.
  bool matches({required int computedV1, required int computedV2}) =>
      crc == computedV1 || crc == computedV2;
}
