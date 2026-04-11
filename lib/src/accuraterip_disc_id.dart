/// AccurateRip disc-ID computation.
///
/// Author: Paul Snow
/// Since: 0.0.1
library;

/// Identifies a disc in the AccurateRip database.
///
/// The AccurateRip lookup URL is derived from [discId1], [discId2],
/// [cddbDiscId], and [trackCount]. Construct an instance directly
/// when the fields are already known, or call
/// [AccurateRipDiscId.fromTrackSampleCounts] to compute the fields
/// from per-track sample counts (e.g. read from FLAC STREAMINFO).
class AccurateRipDiscId {
  /// Create an [AccurateRipDiscId] with the given field values.
  const AccurateRipDiscId({
    required this.discId1,
    required this.discId2,
    required this.cddbDiscId,
    required this.trackCount,
  });

  /// First AccurateRip disc ID — the sum of track start offsets
  /// (each biased by the CD lead-in of 150 sectors) plus the
  /// lead-out sector.
  final int discId1;

  /// Second AccurateRip disc ID — the weighted sum of track start
  /// offsets (each biased by 150 and multiplied by its 1-based
  /// track index) plus the lead-out sector weighted by
  /// `trackCount + 1`.
  final int discId2;

  /// The FreeDB/CDDB disc ID derived from the same track offsets.
  final int cddbDiscId;

  /// The number of audio tracks on the disc.
  final int trackCount;

  /// Compute an [AccurateRipDiscId] from per-track sample counts.
  ///
  /// [trackSampleCounts] is the list of total stereo frame counts
  /// per track, in track order. For a FLAC rip this is the
  /// `totalSamples` field from each track's STREAMINFO block.
  ///
  /// [sampleRate] is the audio sample rate in Hz. For Red Book CDs
  /// it is always 44100, which is the default.
  ///
  /// The AccurateRip protocol measures offsets in CD sectors, where
  /// one sector is 588 stereo frames. Each offset is biased by the
  /// standard 150-sector lead-in used by CD TOCs.
  factory AccurateRipDiscId.fromTrackSampleCounts(
    List<int> trackSampleCounts, {
    int sampleRate = 44100,
  }) {
    final trackCount = trackSampleCounts.length;

    // Per-track start offsets in sectors. Track 1 starts at sector 0.
    final offsets = <int>[0];
    for (var i = 0; i < trackCount - 1; i++) {
      offsets.add(offsets[i] + (trackSampleCounts[i] ~/ 588));
    }
    final leadOutOffset = offsets.last + (trackSampleCounts.last ~/ 588);

    // discId1: Σ (offset + 150) for all tracks, plus (leadOut + 150).
    var id1 = 0;
    for (final offset in offsets) {
      id1 += offset + 150;
    }
    id1 += leadOutOffset + 150;
    id1 &= 0xFFFFFFFF;

    // discId2: Σ (offset + 150) * trackIndex for all tracks, plus
    // (leadOut + 150) * (trackCount + 1).
    var id2 = 0;
    for (var i = 0; i < offsets.length; i++) {
      id2 += (offsets[i] + 150) * (i + 1);
    }
    id2 += (leadOutOffset + 150) * (trackCount + 1);
    id2 &= 0xFFFFFFFF;

    // CDDB disc ID: sum of decimal-digit sums of each track's start
    // time in seconds, modulo 255; packed with the total disc
    // duration in seconds and the track count.
    var digitSumTotal = 0;
    for (final offset in offsets) {
      var seconds = (offset + 150) ~/ 75;
      while (seconds > 0) {
        digitSumTotal += seconds % 10;
        seconds ~/= 10;
      }
    }
    final totalSeconds = (leadOutOffset + 150) ~/ 75 - (offsets[0] + 150) ~/ 75;
    final n = digitSumTotal % 0xFF;
    final cddbId = ((n & 0xFF) << 24) |
        ((totalSeconds & 0xFFFF) << 8) |
        (trackCount & 0xFF);

    return AccurateRipDiscId(
      discId1: id1,
      discId2: id2,
      cddbDiscId: cddbId,
      trackCount: trackCount,
    );
  }
}
