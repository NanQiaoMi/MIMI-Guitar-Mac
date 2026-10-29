import { hashBytes, mutatePersonalData, readAsset, readPersonalData } from '../personal/repository.ts';
import type { PersonalAsset } from '../personal/types.ts';

export interface StoredOriginalScore {
  id: string;
  fileName: string;
  mimeType: string;
  data: ArrayBuffer;
  savedAt: number;
}

/** Imported source bytes live in the same backupable asset store as other personal files. */
export async function saveOriginalScoreFile(id: string, fileName: string, mimeType: string, data: Uint8Array): Promise<void> {
  const bytes = data.slice();
  const assetId = await hashBytes(bytes);
  const asset: PersonalAsset = { id: assetId, mimeType: mimeType || 'application/octet-stream', bytes: bytes.buffer as ArrayBuffer };
  const reference = { id, fileName, mimeType: asset.mimeType, assetId, savedAt: Date.now() };
  await mutatePersonalData((draft) => {
    const index = draft.originals.findIndex((item) => item.id === id);
    if (index < 0) draft.originals.push(reference);
    else draft.originals[index] = reference;
  }, { assets: [asset] });
}

export async function getOriginalScoreFile(id: string): Promise<StoredOriginalScore | null> {
  const reference = (await readPersonalData()).originals.find((item) => item.id === id);
  if (!reference) return null;
  const asset = await readAsset(reference.assetId);
  if (!asset) return null;
  return { id, fileName: reference.fileName, mimeType: reference.mimeType, data: asset.bytes.slice(0), savedAt: reference.savedAt };
}

export async function deleteOriginalScoreFile(id: string): Promise<void> {
  await mutatePersonalData((draft) => { draft.originals = draft.originals.filter((item) => item.id !== id); });
}

export function downloadStoredOriginalScore(file: StoredOriginalScore): void {
  const url = URL.createObjectURL(new Blob([file.data], { type: file.mimeType }));
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = file.fileName;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 2000);
}
