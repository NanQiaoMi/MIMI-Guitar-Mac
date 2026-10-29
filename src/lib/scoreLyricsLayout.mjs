/**
 * Adds one invisible, font-measured lyric line above visible lyrics.
 *
 * AlphaTab places lyrics in a bottom effect band beneath numbered notation.
 * A leading empty line makes that band reserve real text height plus the
 * configured lyric line spacing, so beams and lyrics cannot collapse into the
 * same vertical space. Call this only on a render clone; never persist it.
 *
 * @param {unknown} scoreJson
 * @returns {number} number of beats changed
 */
export function addLyricsTopSpacer(scoreJson) {
  let changed = 0;
  const tracks = Array.isArray(scoreJson?.tracks) ? scoreJson.tracks : [];

  for (const track of tracks) {
    const staves = Array.isArray(track?.staves) ? track.staves : [];
    for (const staff of staves) {
      const bars = Array.isArray(staff?.bars) ? staff.bars : [];
      for (const bar of bars) {
        const voices = Array.isArray(bar?.voices) ? bar.voices : [];
        for (const voice of voices) {
          const beats = Array.isArray(voice?.beats) ? voice.beats : [];
          for (const beat of beats) {
            const lyrics = beat?.lyrics;
            if (!Array.isArray(lyrics) || lyrics[0] === '') continue;
            if (!lyrics.some((line) => typeof line === 'string' && line.trim().length > 0)) continue;

            beat.lyrics = ['', ...lyrics];
            changed++;
          }
        }
      }
    }
  }

  return changed;
}
