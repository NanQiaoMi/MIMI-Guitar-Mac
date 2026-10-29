import { model } from '@coderline/alphatab';

const NOTE_DURATIONS = new Set([1, 2, 4, 8, 16, 32, 64, 128, 256]);
const GUITAR_FAMILY = /guitar|bass|ukulele|banjo|mandolin/i;
const COLLECTOR_DISABLED_MESSAGE = '外部曲谱采集已停用；当前版本不会访问 Songsterr 或写入采集文件。';

function rejectDisabledCollector(): never {
  throw new ScoreSourceError(COLLECTOR_DISABLED_MESSAGE, 503);
}

export class ScoreSourceError extends Error {
  status: number;

  constructor(message: string, status = 502) {
    super(message);
    this.name = 'ScoreSourceError';
    this.status = status;
  }
}

function isPlayableStringTrack(track: any): boolean {
  const description = `${track?.instrument ?? ''} ${track?.name ?? ''}`;
  return GUITAR_FAMILY.test(description) && !/drum|vocal|voice|piano|keyboard/i.test(description);
}

/** Select a guitar-family track while respecting a valid zero-based API index. */
export function selectSongsterrTrackIndex(songMeta: any, preferredIndex?: number): number {
  const tracks = Array.isArray(songMeta?.tracks) ? songMeta.tracks : [];
  const usable = (index: number) => Number.isSafeInteger(index) && index >= 0 && (!tracks.length || isPlayableStringTrack(tracks[index]));

  if (preferredIndex !== undefined && preferredIndex !== null && usable(preferredIndex)) return preferredIndex;

  const rawPopularIndex = songMeta?.popularTrackGuitar;
  const popularIndex = rawPopularIndex === null || rawPopularIndex === undefined || rawPopularIndex === ''
    ? Number.NaN
    : Number(rawPopularIndex);
  if (Number.isSafeInteger(popularIndex) && usable(popularIndex)) return popularIndex;

  const guitarIndex = tracks.findIndex((track: any) => isPlayableStringTrack(track) && track.isEmpty !== true);
  if (guitarIndex >= 0) return guitarIndex;

  const reason = tracks.length ? '没有可导入的吉他、贝斯或尤克里里音轨' : '来源没有提供可确认的吉他音轨索引';
  throw new ScoreSourceError(`Songsterr 曲目无法导入：${reason}`, 422);
}

/** Search Songsterr's current public song index. */
export async function searchSongsterr(query: string): Promise<unknown[]> {
  void query;
  rejectDisabledCollector();
}

/** Fetch one source revision and its selected track with bounded retries and timeouts. */
export async function fetchSongsterrTrackData(songIdValue: number | string, requestedTrackIndex?: number): Promise<never> {
  void songIdValue;
  void requestedTrackIndex;
  rejectDisabledCollector();
}

function quoteAlphaTex(value: unknown): string {
  const safe = String(value ?? '').replace(/[\r\n]+/g, ' ').replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  return `"${safe}"`;
}

function midiPitchName(value: unknown): string {
  const midi = Number(value);
  if (!Number.isFinite(midi) || midi < 0 || midi > 127) {
    throw new ScoreSourceError(`音轨包含无效的调弦音高：${String(value)}`, 422);
  }
  const name = model.Tuning.getTextForTuning(midi, true);
  if (!name) throw new ScoreSourceError(`无法转换 MIDI 调弦音高 ${midi}`, 422);
  return name.toLowerCase();
}

function durationForBeat(beat: any, onInvalid: () => void): { base: number; effect: string } {
  const fallback = Number.isSafeInteger(Number(beat?.type)) && NOTE_DURATIONS.has(Number(beat.type))
    ? Number(beat.type)
    : 4;
  const duration = beat?.duration;
  const numerator = Array.isArray(duration) ? Number(duration[0]) : 1;
  const denominator = Array.isArray(duration) ? Number(duration[1]) : fallback;
  const requestedBase = Number(beat?.type);
  const base = Number.isSafeInteger(requestedBase) && NOTE_DURATIONS.has(requestedBase)
    ? requestedBase
    : (Number.isSafeInteger(denominator) && NOTE_DURATIONS.has(denominator) ? denominator : fallback);

  if (!Number.isSafeInteger(numerator) || numerator <= 0 || !Number.isSafeInteger(denominator) || denominator <= 0) {
    onInvalid();
    return { base, effect: '' };
  }

  let effectNumerator = numerator * base;
  let effectDenominator = denominator;
  const divisor = (a: number, b: number): number => b === 0 ? a : divisor(b, a % b);
  const common = divisor(effectNumerator, effectDenominator);
  effectNumerator /= common;
  effectDenominator /= common;

  if (effectNumerator === effectDenominator) return { base, effect: '' };
  if (effectNumerator * 2 === effectDenominator * 3) return { base, effect: 'd' };
  if (effectNumerator * 4 === effectDenominator * 7) return { base, effect: 'dd' };
  // AlphaTex's tuplet factor is denominator/numerator, so invert the desired duration ratio.
  return { base, effect: `tu ${effectDenominator} ${effectNumerator}` };
}

function keySignatureName(key: any): string | null {
  const count = Number(key?.accidentalCount);
  if (!Number.isSafeInteger(count) || count < -7 || count > 7) return null;
  const minor = String(key?.mode ?? '').toLowerCase() === 'minor';
  const majorKeys = ['cbmajor', 'gbmajor', 'dbmajor', 'abmajor', 'ebmajor', 'bbmajor', 'fmajor', 'cmajor', 'gmajor', 'dmajor', 'amajor', 'emajor', 'bmajor', 'f#major', 'c#major'];
  const minorKeys = ['abminor', 'ebminor', 'bbminor', 'fminor', 'cminor', 'gminor', 'dminor', 'aminor', 'eminor', 'bminor', 'f#minor', 'c#minor', 'g#minor', 'd#minor', 'a#minor'];
  return (minor ? minorKeys : majorKeys)[count + 7] ?? null;
}

function keySignatureLabel(key: any): string {
  const value = keySignatureName(key);
  const match = value?.match(/^([a-g])([b#]?)(major|minor)$/);
  if (!match) return 'Unknown';
  const [, letter, accidental, mode] = match;
  return `${letter.toUpperCase()}${accidental} ${mode}`;
}

function sourceNoteEffects(note: any, beat: any, unmapped: Set<string>): string[] {
  const effects: string[] = [];
  if (note?.letRing || beat?.letRing) effects.push('lr');
  if (note?.vibrato) effects.push('v');
  if (note?.staccato) effects.push('st');
  if (note?.dead) effects.push('x');
  if (note?.tie) effects.push('t');

  const unsupported = ['bend', 'slide', 'hp', 'harmonic', 'ghost', 'accentuated', 'palmMute', 'tremoloPicking'];
  for (const field of unsupported) {
    if (note?.[field]) unmapped.add(field);
  }
  return effects;
}

/** Convert Songsterr's zero-based, high-to-low string positions to AlphaTex's one-based notation. */
export function convertSongsterrToAlphaTex(songMeta: any, trackData: any) {
  const measures = trackData?.measures;
  if (!Array.isArray(measures) || measures.length === 0) {
    throw new ScoreSourceError('音轨没有可转换的小节', 422);
  }

  const tuningSource = Array.isArray(trackData.tuning) && trackData.tuning.length
    ? trackData.tuning
    : model.Tuning.getDefaultTuningFor(Number(trackData.strings) || 6)?.tunings;
  if (!Array.isArray(tuningSource) || tuningSource.length < 1 || tuningSource.length > 16) {
    throw new ScoreSourceError('音轨调弦数据无效，无法安全转换', 422);
  }
  const stringCount = Number(trackData.strings) || tuningSource.length;
  if (!Number.isSafeInteger(stringCount) || stringCount !== tuningSource.length) {
    throw new ScoreSourceError('音轨弦数与调弦数据长度不一致', 422);
  }

  const tempoEvents = Array.isArray(trackData.automations?.tempo) ? trackData.automations.tempo : [];
  const initialTempo = tempoEvents.find((event: any) => Number(event?.measure) === 0 && Number(event?.position ?? 0) === 0)?.bpm;
  const bpmValue = Number(initialTempo ?? trackData.bpm ?? songMeta?.bpm ?? 80);
  const bpm = Number.isFinite(bpmValue) && bpmValue >= 20 && bpmValue <= 300 ? Math.round(bpmValue) : 80;
  const capoValue = Number(trackData.capo ?? 0);
  const capo = Number.isSafeInteger(capoValue) && capoValue >= 0 && capoValue <= 24 ? capoValue : 0;
  const lines = [
    `\\title ${quoteAlphaTex(songMeta?.title || 'Untitled')}`,
    `\\artist ${quoteAlphaTex(songMeta?.artist || 'Unknown')}`,
    `\\tempo ${bpm}`,
    ...(capo > 0 ? [`\\capo ${capo}`] : []),
    `\\tuning ${tuningSource.map(midiPitchName).join(' ')}`,
    '.',
    '',
  ];
  const detectedChords: string[] = [];
  const previewTabMatrix: any[] = [];
  const unmappedEffects = new Set<string>();
  let skippedNotes = 0;
  let invalidDurations = 0;
  let ignoredExtraVoices = 0;
  let unsupportedSourceFeatures = 0;
  let previousSignature = '';
  let previousKey = '';
  let firstKeyLabel = 'Unknown';
  let activeTempo = bpm;
  const tempoEventsByMeasure = new Map<number, any[]>();
  for (const event of tempoEvents) {
    const measureIndex = Number(event?.measure);
    const eventBpm = Number(event?.bpm);
    const position = Number(event?.position ?? 0);
    if (!Number.isSafeInteger(measureIndex) || measureIndex < 0 || measureIndex >= measures.length || !Number.isFinite(eventBpm) || eventBpm < 20 || eventBpm > 300 || !Number.isFinite(position) || position < 0 || position > 1) {
      unsupportedSourceFeatures++;
      continue;
    }
    const events = tempoEventsByMeasure.get(measureIndex) ?? [];
    events.push({ bpm: Math.round(eventBpm), position });
    tempoEventsByMeasure.set(measureIndex, events);
  }
  if (trackData.automations && typeof trackData.automations === 'object') {
    unsupportedSourceFeatures += Object.keys(trackData.automations).filter((field) => field !== 'tempo').length;
  }

  for (let mIdx = 0; mIdx < measures.length; mIdx++) {
    const measure = measures[mIdx];
    const voices = Array.isArray(measure?.voices) ? measure.voices : [];
    const voice = voices.find((candidate: any) => Array.isArray(candidate?.beats)) ?? null;
    if (voices.length > 1) ignoredExtraVoices += voices.length - 1;

    const prefix: string[] = [];
    for (const event of tempoEventsByMeasure.get(mIdx) ?? []) {
      if (event.bpm !== activeTempo) {
        prefix.push(event.position === 0
          ? `\\tempo ${event.bpm}`
          : `\\tempo (${event.bpm} ${quoteAlphaTex('')} ${event.position})`);
        activeTempo = event.bpm;
      }
    }
    if (Array.isArray(measure?.signature) && measure.signature.length >= 2) {
      const [numerator, denominator] = measure.signature.map(Number);
      const signature = `${numerator}/${denominator}`;
      if (Number.isSafeInteger(numerator) && numerator > 0 && Number.isSafeInteger(denominator) && denominator > 0 && signature !== previousSignature) {
        prefix.push(`\\ts ${numerator} ${denominator}`);
        previousSignature = signature;
      } else if (signature !== previousSignature) {
        unsupportedSourceFeatures++;
      }
    }
    const key = keySignatureName(measure?.keySignature);
    if (key && key !== previousKey) {
      prefix.push(`\\ks ${key}`);
      previousKey = key;
      if (firstKeyLabel === 'Unknown') firstKeyLabel = keySignatureLabel(measure.keySignature);
    } else if (measure?.keySignature && !key) {
      unsupportedSourceFeatures++;
    }
    const marker = String(measure?.marker?.text ?? '').trim();
    if (marker) prefix.push(`\\section ${quoteAlphaTex(marker)}`);

    const beatTokens: string[] = [];
    const measureNotes: Array<{ fret: number; string: number }> = [];
    let measureChord = '';
    const beats = Array.isArray(voice?.beats) ? voice.beats : [];
    if (beats.length === 0) beatTokens.push(':4 r');

    for (const beat of beats) {
      const duration = durationForBeat(beat, () => { invalidDurations++; });
      const chordName = String(beat?.chord?.text ?? '').trim();
      if (chordName && !detectedChords.includes(chordName)) detectedChords.push(chordName);
      if (chordName && !measureChord) measureChord = chordName;

      const rawNotes = Array.isArray(beat?.notes) ? beat.notes : [];
      const noteTokens: string[] = [];
      for (const note of rawNotes) {
        if (note?.rest) continue;
        const fret = Number(note?.fret);
        const sourceString = Number(note?.string);
        if (!Number.isSafeInteger(fret) || fret < 0 || !Number.isSafeInteger(sourceString) || sourceString < 0 || sourceString >= stringCount) {
          skippedNotes++;
          continue;
        }
        const alphaString = sourceString + 1;
        const effects = sourceNoteEffects(note, beat, unmappedEffects);
        const effectText = effects.length ? `{ ${effects.join(' ')} }` : '';
        noteTokens.push(`${fret}.${alphaString}${effectText}`);
        measureNotes.push({ fret, string: alphaString });
      }

      const content = beat?.rest || noteTokens.length === 0
        ? 'r'
        : noteTokens.length === 1 ? noteTokens[0] : `(${noteTokens.join(' ')})`;
      const durationEffect = duration.effect ? ` { ${duration.effect} }` : '';
      beatTokens.push(`:${duration.base} ${content}${durationEffect}`);
    }

    lines.push(`${prefix.length ? `${prefix.join(' ')} ` : ''}${beatTokens.join(' ')} |`);

    if (mIdx < 4) {
      previewTabMatrix.push({
        measure: mIdx + 1,
        chordName: measureChord || 'Tab',
        notes: measureNotes.slice(0, 4).map((note, index) => ({ ...note, isRoot: index === 0 })),
      });
    }
  }

  const warnings: string[] = [];
  if (skippedNotes) warnings.push(`${skippedNotes} 个音符缺少有效品位或弦位，已跳过`);
  if (unmappedEffects.size) warnings.push(`以下技法尚未映射到 AlphaTex：${[...unmappedEffects].sort().join('、')}`);
  if (invalidDurations) warnings.push(`${invalidDurations} 个无法识别的节拍时值使用了安全的四分音符时值`);
  if (ignoredExtraVoices) warnings.push(`${ignoredExtraVoices} 个额外声部暂未导入`);
  if (unsupportedSourceFeatures) warnings.push(`${unsupportedSourceFeatures} 处来源乐理标记暂未完整映射`);
  if (/12\s*[- ]?\s*string|12弦/i.test(String(trackData.name ?? songMeta?.trackName ?? ''))) {
    warnings.push('来源标记为 12 弦音轨；当前弦位映射未包含复弦信息');
  }

  return {
    alphaTex: lines.join('\n'),
    chords: detectedChords.slice(0, 8),
    previewTabMatrix,
    measuresCount: measures.length,
    key: firstKeyLabel,
    bpm,
    capo,
    warnings,
  };
}

/** Disabled until fetched sources can be persisted to the catalog atomically. */
export async function ingestSongFromSongsterr(songIdValue: number | string, customId: string | null = null): Promise<never> {
  void songIdValue;
  void customId;
  rejectDisabledCollector();
}
