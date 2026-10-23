/** Convert AlphaTab's 0..16 track volume to the player's 0..100 control value. */
export function trackVolumePercent(volume) {
  const value = Number.isFinite(volume) ? Math.min(16, Math.max(0, volume)) : 16;
  return Math.round((value / 16) * 100);
}

/** Capture each staff's capo before applying any player override. */
export function captureSourceCapos(score) {
  if (!Array.isArray(score?.tracks)) return [];
  return score.tracks.map((track) => (Array.isArray(track?.staves) ? track.staves : []).map((staff) => (
    Number.isFinite(staff?.capo) ? staff.capo : 0
  )));
}

/** Apply either the original per-staff capos or one explicit numeric override. */
export function applyCapoSelection(score, sourceCapos, selection) {
  if (!Array.isArray(score?.tracks)) return score;
  const useSourceCapo = selection?.useSourceCapo === true;
  const override = selection?.capo;
  for (let trackIndex = 0; trackIndex < score.tracks.length; trackIndex++) {
    const staves = score.tracks[trackIndex]?.staves;
    if (!Array.isArray(staves)) continue;
    for (let staffIndex = 0; staffIndex < staves.length; staffIndex++) {
      if (useSourceCapo) {
        const sourceCapo = sourceCapos?.[trackIndex]?.[staffIndex];
        if (Number.isFinite(sourceCapo)) staves[staffIndex].capo = sourceCapo;
      } else if (Number.isFinite(override)) {
        staves[staffIndex].capo = override;
      }
    }
  }
  return score;
}

export function primarySourceCapo(sourceCapos, trackIndex) {
  const capo = sourceCapos?.[trackIndex]?.[0];
  return Number.isFinite(capo) ? capo : 0;
}

export function formatCapoValue(value) {
  if (!Number.isFinite(value)) return '原谱';
  if (value === -1) return '降半调调弦';
  if (value === 0) return '不夹';
  return value > 0 ? `${value}品` : `${value}半音`;
}

/** Summarize source capo values without hiding mixed tracks or values above 6. */
export function sourceCapoSummary(sourceCapos) {
  if (!Array.isArray(sourceCapos) || sourceCapos.length === 0) return formatCapoValue(0);
  const perTrack = sourceCapos.map((staves) => [...new Set(
    (Array.isArray(staves) ? staves : []).filter(Number.isFinite)
  )]);
  const values = perTrack.flat();
  if (values.length === 0) return formatCapoValue(0);
  const unique = [...new Set(values)];
  if (unique.length === 1) return formatCapoValue(unique[0]);
  return perTrack.map((trackValues, trackIndex) => {
    if (trackValues.length === 0) return null;
    return `第${trackIndex + 1}轨 ${trackValues.map(formatCapoValue).join('/')}`;
  }).filter(Boolean).join('；');
}

function samePracticeScoreSource(left, right) {
  return !!left && !!right && left.id === right.id && left.source === right.source
    && left.sourceId === right.sourceId && left.scoreUrl === right.scoreUrl
    && left.assetId === right.assetId && left.originalAssetId === right.originalAssetId
    && left.projectId === right.projectId;
}

/** Do not let a stale catalog placeholder replace bytes already verified by this player. */
export function shouldKeepVerifiedPracticeScore(current, incoming) {
  return current?.source === 'catalog' && incoming?.source === 'catalog'
    && samePracticeScoreSource(current, incoming)
    && current.revision !== 'unverified' && incoming.revision === 'unverified';
}

/** Resolve the actual catalog request URL without storing it in the score identity. */
export function resolvedCatalogScoreUrl(score, fallbackUrl) {
  if (typeof score?.scoreUrl === 'string' && score.scoreUrl.length > 0) return score.scoreUrl;
  if (typeof score?.sourceId === 'string' && score.sourceId.length > 0) {
    return `/api/tabs/${encodeURIComponent(score.sourceId)}/download`;
  }
  return fallbackUrl;
}

/**
 * Keep durable progress anchored to the last position AlphaTab confirmed.
 * @param {{tick:number,timeMs:number}|null} confirmed
 * @param {{tick:number,timeMs:number}} fallback
 * @param {{tick:number,timeMs:number}|null} naturalEnd
 * @returns {{tick:number,timeMs:number}}
 */
export function practicePositionSnapshot(confirmed, fallback, naturalEnd = null) {
  const position = naturalEnd ?? confirmed ?? fallback;
  return { tick: position.tick, timeMs: position.timeMs };
}

function normalizedTick(value) {
  if (!Number.isFinite(value)) return null;
  const rounded = Math.round(value);
  return Number.isSafeInteger(rounded) ? rounded : null;
}

function clampedPositionTick(tick, endTick) {
  const normalized = normalizedTick(tick);
  const normalizedEnd = normalizedTick(endTick);
  if (normalized === null || normalizedEnd === null || normalizedEnd < 0) return null;
  return Math.min(normalizedEnd, Math.max(0, normalized));
}

/** AlphaTab treats the score end as exclusive; inspect the final tick for end metadata. */
export function beatLookupTick(tick, endTick) {
  const positionTick = clampedPositionTick(tick, endTick);
  const normalizedEnd = normalizedTick(endTick);
  if (positionTick === null || normalizedEnd === null || normalizedEnd <= 0) return tick;
  return positionTick === normalizedEnd ? Math.max(0, normalizedEnd - 1) : positionTick;
}

/** While a seek receipt is pending, ignore playback or out-of-order seek events. */
export function shouldIgnorePositionDuringSeek(targetTick, position) {
  if (targetTick == null) return false;
  return position?.isSeek !== true || !Number.isFinite(position.currentTick)
    || Math.abs(position.currentTick - targetTick) > 1;
}

/**
 * AlphaTab pauses a repeated beat by seeking to its first source occurrence.
 * A differing unfolded/source beat start predicts that remap; an active A/B
 * range is a second guard when the exposed position has already left the range.
 * @param {{tick:number,unfoldedBeatStartTick:number|null,sourceBeatStartTick:number|null,rangeStartTick?:number|null,rangeEndTick?:number|null}|null} captured
 * @param {number} reportedTick
 * @returns {number|null}
 */
export function pausePositionRestoreTarget(captured, reportedTick) {
  const capturedTick = normalizedTick(captured?.tick);
  const reported = normalizedTick(reportedTick);
  if (capturedTick === null) return null;

  const unfoldedStart = normalizedTick(captured.unfoldedBeatStartTick);
  const sourceStart = normalizedTick(captured.sourceBeatStartTick);
  const sourceOccurrenceRemap = unfoldedStart !== null && sourceStart !== null
    && unfoldedStart !== sourceStart;

  const rangeStart = normalizedTick(captured.rangeStartTick);
  const rangeEnd = normalizedTick(captured.rangeEndTick);
  const hasValidRange = rangeStart !== null && rangeEnd !== null && rangeEnd > rangeStart;
  const capturedInsideRange = hasValidRange && capturedTick >= rangeStart && capturedTick <= rangeEnd;
  const pauseLeftRange = capturedInsideRange && reported !== null
    && (reported < rangeStart || reported >= rangeEnd);

  return sourceOccurrenceRemap || pauseLeftRange ? capturedTick : null;
}

/** Resolve bar/beat and the current beat's exclusive end from AlphaTab's unfolded lookup. */
export function positionBeatMetadata(lookup, tick, endTick) {
  const empty = { bar: 0, beat: 0, beatEndTick: 0, repeatAmbiguous: false };
  const positionTick = clampedPositionTick(tick, endTick);
  const normalizedEnd = normalizedTick(endTick);
  if (!lookup || positionTick === null || normalizedEnd === null || normalizedEnd <= 0) {
    return empty;
  }

  // Only MidiTickLookupFindBeatResult.end is an unfolded, absolute tick.
  // beatLookup.end is relative to its enclosing master bar.
  const beatEndTick = normalizedTick(lookup.end);
  if (beatEndTick === null || beatEndTick < positionTick || beatEndTick > normalizedEnd) return empty;

  const beat = lookup.beat;
  const masterBar = beat?.voice?.bar?.masterBar ?? lookup.masterBar?.masterBar;
  const barIndex = masterBar?.index;
  const bar = Number.isSafeInteger(barIndex) && barIndex >= 0 ? barIndex + 1 : 0;
  const numerator = Number.isFinite(masterBar?.timeSignatureNumerator) && masterBar.timeSignatureNumerator > 0
    ? masterBar.timeSignatureNumerator : 4;
  const denominator = Number.isFinite(masterBar?.timeSignatureDenominator) && masterBar.timeSignatureDenominator > 0
    ? masterBar.timeSignatureDenominator : 4;
  const ticksPerBeat = (4 / denominator) * 960;
  const playbackStart = beat?.playbackStart;
  let beatNumber = 0;
  if (Number.isFinite(playbackStart) && ticksPerBeat > 0) {
    // Beat.playbackStart is relative to its bar; absolutePlaybackStart adds masterBar.start.
    const rawBeat = Math.floor(playbackStart / ticksPerBeat) + 1;
    beatNumber = Math.min(numerator, Math.max(1, rawBeat));
  } else if (Number.isSafeInteger(beat?.index) && beat.index >= 0) {
    beatNumber = Math.min(numerator, (beat.index % numerator) + 1);
  }

  const repeatGroup = masterBar?.repeatGroup;
  return {
    bar,
    beat: beatNumber,
    beatEndTick,
    repeatAmbiguous: !!repeatGroup?.isOpened && (repeatGroup.masterBars?.length ?? 0) > 1,
  };
}
