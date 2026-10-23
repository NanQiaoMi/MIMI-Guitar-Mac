export interface ActiveNotePosition {
  x: number;
  y: number;
  pitch?: number;
}

export interface PaperWatermarkNote {
  x: number;
  y: number;
  glyph: string;
  size: number;
  rotation: number;
  alpha: number;
  maxAlpha: number;
  scale: number;
  life: number;
  decay: number;
  inkWashRadius: number;
}

export interface PaperAcousticWave {
  x: number;
  y: number;
  radius: number;
  maxRadius: number;
  vRadius: number;
  alpha: number;
  maxAlpha: number;
  lineWidth: number;
  isStaveLine: boolean;
}

export const PAPER_GLYPHS = ['♪', '♫', '♩', '♬', '𝄞', '𝄢', '✦'] as const;

/**
 * Creates an elegant tactile paper watermark note impression
 */
export function createPaperWatermarkNote(x: number, y: number, pitch?: number): PaperWatermarkNote {
  const glyph = PAPER_GLYPHS[Math.floor(Math.random() * PAPER_GLYPHS.length)];
  const size = 18 + Math.random() * 10;
  const maxLife = 50 + Math.floor(Math.random() * 30); // ~1.2s at 60fps

  return {
    x: x + (Math.random() - 0.5) * 8,
    y: y + (Math.random() - 0.5) * 6,
    glyph,
    size,
    rotation: (Math.random() - 0.5) * 0.15,
    alpha: 0.28,
    maxAlpha: 0.28,
    scale: 0.85,
    life: 1.0,
    decay: 1 / maxLife,
    inkWashRadius: 16 + Math.random() * 12,
  };
}

/**
 * Creates subtle concentric acoustic paper ripples
 */
export function createPaperAcousticWaves(x: number, y: number, pitch?: number): PaperAcousticWave[] {
  const wave1: PaperAcousticWave = {
    x,
    y,
    radius: 6,
    maxRadius: 65 + Math.random() * 25,
    vRadius: 1.2,
    alpha: 0.18,
    maxAlpha: 0.18,
    lineWidth: 1.0,
    isStaveLine: false,
  };

  const wave2: PaperAcousticWave = {
    x,
    y,
    radius: 3,
    maxRadius: 40 + Math.random() * 15,
    vRadius: 0.8,
    alpha: 0.12,
    maxAlpha: 0.12,
    lineWidth: 0.75,
    isStaveLine: true,
  };

  return [wave1, wave2];
}
