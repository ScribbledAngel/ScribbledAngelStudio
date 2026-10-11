import 'package:flutter_test/flutter_test.dart';
import 'package:scribbled_angel_studio/data/export_service.dart';

/// Covers [pickAudioSampleRate] - export muxes the shot's own audio in by
/// decoding it to raw PCM and feeding it to the encoder one video-frame's
/// worth at a time, which only works when a standard AAC sample rate
/// divides evenly by the export frame rate. The actual decode/mux pipeline
/// needs real device codecs, so it's checked by hand (see
/// docs/rotoscoping_qa_checklist.md); this covers the rate-picking math.
void main() {
  group('pickAudioSampleRate', () {
    test('common animation frame rates all find a sample rate', () {
      for (final fps in [4, 8, 12, 24]) {
        final rate = pickAudioSampleRate(fps);
        expect(rate, isNotNull, reason: 'fps=$fps should find a sample rate');
        expect(rate! % fps, 0, reason: 'fps=$fps: $rate must divide evenly by fps');
      }
    });

    test('picks the loudest-quality standard rate available', () {
      expect(pickAudioSampleRate(12), 48000);
      expect(pickAudioSampleRate(24), 48000);
      expect(pickAudioSampleRate(4), 48000);
    });

    test('frame rates with no evenly-dividing standard rate return null', () {
      for (final fps in [11, 13, 17, 19, 23, 29]) {
        expect(pickAudioSampleRate(fps), isNull, reason: 'fps=$fps has no exact-dividing standard rate');
      }
    });

    test('zero or negative fps returns null', () {
      expect(pickAudioSampleRate(0), isNull);
      expect(pickAudioSampleRate(-5), isNull);
    });
  });
}
