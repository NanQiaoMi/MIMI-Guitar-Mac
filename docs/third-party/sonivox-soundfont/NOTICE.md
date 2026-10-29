# SONiVOX SoundFont notice

`public/soundfonts/sonivox.sf2` is copied byte-for-byte from the locally installed
`@coderline/alphatab` npm package, version `1.8.4`, at
`dist/soundfont/sonivox.sf2`. No network download or conversion was used.

SHA-256: `4978cf37e7164206f2d22dc4fdf4020ffe040787210bf781e31bdc79961f59ef`.

The package includes the upstream `README.md` and `LICENSE`; copies are kept in
this directory as `README-source.md` and `LICENSE.txt`. The SoundFont license
identifies Copyright (c) 2004-2006 Sonic Network Inc. and grants use under the
Apache License, Version 2.0. The README says the soundfont is based on the
SONiVOX EAS synthesizer, part of the Android Open Source Project.

This asset is used as the single General MIDI source so each requested bank and
program resolves to its actual preset in the same complete soundfont.
