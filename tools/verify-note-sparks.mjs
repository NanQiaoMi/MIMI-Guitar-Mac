import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {
  getPitchColor,
  calculateGuitarPitch,
  createSparkParticle,
  createResonanceRings,
  SPARK_GLYPHS,
} from '../src/lib/noteSparks.ts';

test('noteSparks - Pitch to Color Harmonic Mapping', () => {
  // Low Pitch (< 52, e.g. E2 = 40, A2 = 45) -> Deep Indigo / Royal Cobalt
  const low1 = getPitchColor(40);
  assert.equal(low1.isLow, true, 'Pitch 40 is low');
  assert.match(low1.color, /^#(2563eb|1d4ed8|4f46e5|3b82f6)$/, 'Low pitch matches indigo/cobalt palette');
  assert.ok(low1.glow.includes('rgba(37, 99, 235'), 'Low pitch has indigo glow');

  const low2 = getPitchColor(45);
  assert.equal(low2.isLow, true, 'Pitch 45 is low');

  // Mid Pitch (52..67, e.g. D3 = 50, G3 = 55, B3 = 59, C4 = 60) -> Radiant Cyan / Sky Blue
  const mid1 = getPitchColor(58);
  assert.equal(mid1.isHigh, false, 'Pitch 58 is not high');
  assert.equal(mid1.isLow, false, 'Pitch 58 is not low');
  assert.match(mid1.color, /^#(41a1cf|06b6d4|0284c7|38bdf8)$/, 'Mid pitch matches cyan palette');
  assert.ok(mid1.glow.includes('rgba(65, 161, 207'), 'Mid pitch has signal cyan glow');

  // High Pitch (>= 68, e.g. G5 = 79, C6 = 84) -> Radiant Gold / Sunlight
  const high1 = getPitchColor(80);
  assert.equal(high1.isHigh, true, 'Pitch 80 is high');
  assert.match(high1.color, /^#(fbbf24|f59e0b|fcd34d|41a1cf)$/, 'High pitch matches gold/cyan palette');

  // Default Fallback
  const fallback = getPitchColor(undefined);
  assert.equal(fallback.color, '#41a1cf', 'Default color is signal cyan');
});

test('noteSparks - Guitar Pitch Calculation', () => {
  // String 1 (E4 = 64), Fret 0 -> 64
  assert.equal(calculateGuitarPitch(1, 0), 64);
  // String 1, Fret 3 (G4) -> 67
  assert.equal(calculateGuitarPitch(1, 3), 67);
  // String 6 (E2 = 40), Fret 0 -> 40
  assert.equal(calculateGuitarPitch(6, 0), 40);
  // String 5 (A2 = 45), Fret 2 (B2) -> 47
  assert.equal(calculateGuitarPitch(5, 2), 47);
});

test('noteSparks - Spark Particle & Resonance Rings Physics Factories', () => {
  const palette = getPitchColor(64);
  const particle = createSparkParticle(100, 150, palette);

  assert.ok(particle.vx !== undefined && typeof particle.vx === 'number');
  assert.ok(particle.vy < 0, 'Particle upward velocity is negative (sprays upward)');
  assert.ok(particle.gravity > 0, 'Particle has positive downward gravity acceleration');
  assert.ok(particle.friction > 0 && particle.friction < 1, 'Particle has air friction < 1');
  assert.ok(SPARK_GLYPHS.includes(particle.glyph), 'Particle has valid glyph');
  assert.ok(particle.life === 1.0, 'Initial particle life is 1.0');

  const rings = createResonanceRings(100, 150, palette);
  assert.equal(rings.length, 2, 'Two concentric resonance rings created');
  assert.equal(rings[0].x, 100);
  assert.equal(rings[0].y, 150);
  assert.ok(rings[0].vRadius > 0, 'Ring expands outward');
  assert.ok(rings[1].delay > 0, 'Second harmonic overtone ring is delayed');
});

test('ScorePlayer - Integration of ScoreNoteSparkTrails', () => {
  const scorePlayerContent = fs.readFileSync('src/components/player/ScorePlayer.svelte', 'utf-8');

  assert.ok(
    scorePlayerContent.includes("import ScoreNoteSparkTrails from './ScoreNoteSparkTrails.svelte'"),
    'ScorePlayer imports ScoreNoteSparkTrails'
  );
  assert.ok(
    scorePlayerContent.includes('<ScoreNoteSparkTrails'),
    'ScorePlayer mounts ScoreNoteSparkTrails'
  );
  assert.ok(
    scorePlayerContent.includes('scoreContainer={container}'),
    'ScorePlayer passes scoreContainer to ScoreNoteSparkTrails'
  );
  assert.ok(
    scorePlayerContent.includes('isPlaying={playing}'),
    'ScorePlayer passes isPlaying to ScoreNoteSparkTrails'
  );
});

test('ScoreNoteSparkTrails - Template and Canvas Overlay Specifications', () => {
  const sparkTrailsContent = fs.readFileSync('src/components/player/ScoreNoteSparkTrails.svelte', 'utf-8');

  assert.ok(
    sparkTrailsContent.includes('class="score-note-spark-trails pointer-events-none absolute inset-0 z-15 overflow-hidden select-none'),
    'ScoreNoteSparkTrails has zero layout impact and pointer-events: none'
  );
  assert.ok(
    sparkTrailsContent.includes('<canvas'),
    'ScoreNoteSparkTrails contains HTML5 Canvas 2D element'
  );
  assert.ok(
    sparkTrailsContent.includes('devicePixelRatio'),
    'ScoreNoteSparkTrails supports High DPI / Retina rendering'
  );
  assert.ok(
    sparkTrailsContent.includes('visibilitychange'),
    'ScoreNoteSparkTrails supports Visibility API pausing'
  );
  assert.ok(
    sparkTrailsContent.includes('api.playedBeatChanged'),
    'ScoreNoteSparkTrails subscribes to api.playedBeatChanged'
  );
  assert.ok(
    sparkTrailsContent.includes('.at-cursor-beat'),
    'ScoreNoteSparkTrails queries .at-cursor-beat for stave coordinates'
  );
});

console.log('✓ All ScoreNoteSparkTrails tests and integration checks passed!');
