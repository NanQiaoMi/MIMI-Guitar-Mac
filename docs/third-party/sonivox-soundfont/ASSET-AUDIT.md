# SoundFont identity audit

This audit reads the existing local SF2 files and AlphaTab's installed package.
It does not modify the existing `public/storage/soundfonts` media.

## General MIDI source

- The project contains the installed `@coderline/alphatab` `1.8.4` file at
  `node_modules/@coderline/alphatab/dist/soundfont/sonivox.sf2`. The repository
  copy at `public/soundfonts/sonivox.sf2` has the same SHA-256:
  `4978cf37e7164206f2d22dc4fdf4020ffe040787210bf781e31bdc79961f59ef`.
- The SF2 tables parse as 132 presets: all 128 bank 0 GM programs and bank 128
  kits 0, 8, 32, and 40. The score player now verifies a requested bank/program and its
  instrument/sample references before passing the full file to AlphaTab.
- In the complete bank, program 24 is `Nylon-str.Gt`, program 25 is
  `Steel-str.Gt`, and program 89 is `Warm Pad`; the requested programs have
  non-empty, distinct sample-reference sets.

## Existing split and fast files

The 131 local storage SF2 files (numeric `0.sf2` through `128.sf2`, plus the two
fast files) all have valid RIFF/SF2 container tables. The inventory has 139
preset records because several split/fast files include extra presets.

- `24.sf2`, `25.sf2`, `acoustic_guitar_fast.sf2`, and `ukulele_fast.sf2` are
  byte-identical: SHA-256
  `e57ba29a8040ed9afd336e0ebe2bb39090369cd1bd14e1e476f01be9e5089b38`.
  They contain bank 0/program 0 `Ukulele Acoustic`, program 24 `Ukulele Nylon`,
  and program 25 `Ukulele Steel`. Their guitar-labelled files therefore do not
  contain GM Nylon Guitar or Steel Guitar presets.
- The Nylon preset references the `TyrosNylon0` instrument and its 11 `g__*`
  sample zones. The Steel preset references `TyrosNylon0` and `TyrosNylon1`;
  these aliases are not the GM 24/25 instrument identities.
- `89.sf2` and `90.sf2` are byte-identical at SHA-256
  `7faf457825e06ef6beecfb7bedcd220df620de73e424b0c3a33cbb54dc02c825`. Both
  contain only bank 0/program 90 `Poly Synth`; the split files do not provide
  program 89.
- The unsafe project-local preset collisions are bank 0/programs 0, 24, 25,
  and 90. In particular, appending the fast file exposes its extra piano and
  guitar-numbered presets, while loading by numeric filename can select the
  wrong program identity.

## Runtime handling

Standard score and workbench GM requests use the pinned complete Sonivox file.
An explicitly marked source-ukulele request for bank 0/program 0, 24, or 25
uses the existing local Uke file after filtering its `phdr` table to the
requested preset plus the SF2 `EOP` sentinel. The source preset bag/generator
indexes are preserved because these legacy tables reuse/reset indexes; actual
AlphaTab offline rendering tests verify the filtered 0/24/25 payloads produce
non-silent PCM. The loader pins and checks the source SHA-256, and fails on a
missing requested preset rather than substituting another one.
