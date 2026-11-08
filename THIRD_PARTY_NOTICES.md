# Free components and data

ORBIT's application code is MIT licensed. Third-party components retain their original licenses.

- Flutter / Dart: BSD-3-Clause, https://github.com/flutter/flutter and https://github.com/dart-lang/sdk
- file_selector: BSD-3-Clause, https://github.com/flutter/packages/tree/main/packages/file_selector
- archive: MIT, https://pub.dev/packages/archive (streaming ZIP single-file project container); posix: MIT and ffi: BSD-3-Clause, as transitive dependencies. See the locked package licenses.
- NumPy / SciPy: BSD-3-Clause, https://numpy.org and https://scipy.org
- SoundFile: BSD-3-Clause; libsndfile: LGPL, https://github.com/bastibe/python-soundfile
- h5py: BSD-3-Clause, https://www.h5py.org
- The three-band EQ is an original implementation of the biquad formulas documented in the W3C Audio EQ Cookbook (adapted with permission from Robert Bristow-Johnson): https://www.w3.org/TR/audio-eq-cookbook/. No third-party plugin binary is bundled.
- PyTorch and Demucs: their respective BSD/MIT licenses; see https://github.com/pytorch/pytorch and https://github.com/facebookresearch/demucs. Downloaded model weights retain the terms published by the model author.
- FFmpeg is discovered locally, not bundled. Its license depends on the selected build. https://ffmpeg.org/legal.html

## KEMAR head-related transfer function

`assets/kemar.sofa` contains MIT KEMAR large-pinna HRIR measurements in SOFA format.
The dataset states: "This HRTF data is provided without any usage restrictions. It is requested that you cite Gardner and Martin (1995) when using this data for research or commercial applications."

Citation: W. G. Gardner and K. D. Martin, "HRTF measurements of a KEMAR," Journal of the Acoustical Society of America 97, 3907–3908 (1995).

The demo project contains only procedural rain and wind. No commercial music, private recordings, stems, model weights, Python runtime or FFmpeg executable are included.

Dataset origin and redistribution statement: https://sound.media.mit.edu/resources/KEMAR.html
SOFA distribution: https://sofacoustics.org/data/database/mit/mit_kemar_large_pinna.sofa
The MIT Media Laboratory dataset terms are separate from ORBIT's MIT software license. The upstream statement permits use without restrictions with author citation for research/commercial applications; cite Gardner and Martin (1995) as above.

## Redistributed notices

Unmodified package license files are included in `third_party/`. Flutter's generated `data/flutter_assets/NOTICES.Z` is included in the Windows package and contains additional Flutter/engine/package notices. Python audio packages, Demucs weights and FFmpeg are installed separately and are not covered by ORBIT's license.

KEMAR conversion credit: Piotr Majdak and Michael Mihocic, Acoustics Research Institute, OeAW. The SOFA file retains its source, citation, conversion and license metadata.
