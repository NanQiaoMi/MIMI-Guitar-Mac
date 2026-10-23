<script lang="ts">
  import { onMount } from 'svelte';
  import { exportPersonalBackup, previewBackup, restoreBackup, MAX_PERSONAL_BACKUP_BYTES, type BackupPreview } from '../lib/personal/backup.ts';
  import {
    cancelPersonalBackupVolumesPreview,
    MAX_PERSONAL_BACKUP_TOTAL_BYTES,
    MAX_PERSONAL_BACKUP_VOLUMES,
    PERSONAL_BACKUP_VOLUME_BYTES as MAX_PERSONAL_BACKUP_VOLUME_BYTES,
    MAX_PERSONAL_BACKUP_MANIFEST_BYTES,
    preparePersonalBackupVolumes,
    previewPersonalBackupVolumes,
    restorePersonalBackupVolumes,
    type BackupVolumePreview,
    type PersonalBackupVolumePlan,
  } from '../lib/personal/backupVolumes.ts';
  import { clearExpiredPersonalRestoreStages, getPersonalMigrationWarnings, readPersonalAssetMetadata, readPersonalData, retryPersonalDataMigration, subscribePersonalData, subscribePersonalStorageUpgrade } from '../lib/personal/repository.ts';
  import { countPackedPersonalBackupVolumes, MAX_PERSONAL_BACKUP_ASSETS, MAX_PERSONAL_BACKUP_ASSET_BYTES, MAX_PERSONAL_BACKUP_ENTITIES } from '../lib/personal/limits.ts';
  import type { PersonalData, PersonalDataSnapshot } from '../lib/personal/types.ts';
  import { fadeMotion, registerMotionSurface } from '../lib/ui/motion.ts';

  let data = $state<PersonalData | null>(null);
  let preview = $state.raw<BackupPreview | null>(null);
  let file = $state<File | null>(null);
  let volumeManifestFile = $state<File | null>(null);
  let volumeFiles = $state<File[]>([]);
  let volumePreview = $state.raw<BackupVolumePreview | null>(null);
  let volumePlan = $state.raw<PersonalBackupVolumePlan | null>(null);
  let readyVolume = $state.raw<Blob | null>(null);
  let readyVolumeSequence = $state(0);
  let initiatedVolumes = $state<number[]>([]);
  let manifestDownloadInitiated = $state(false);
  let volumeProgress = $state('');
  let volumeBackupBusy = $state(false);
  let storageUpgrade = $state(0);
  let operationAbort: AbortController | null = null;
  let busy = $state(false);
  let loading = $state(true);
  let error = $state('');
  let notice = $state('');
  let migrationWarnings = $state<string[]>([]);
  let backupAssetBytes = $state<number | null>(null);
  let backupVolumeCount = $state<number | null>(null);
  let backupAssetMetadataError = $state('');
  let componentActive = true;
  let reloadGeneration = 0;

  async function reload() {
    const generation = ++reloadGeneration;
    const next = await readPersonalData();
    const ids = [...new Set([
      ...next.scores.flatMap((score) => [score.assetId, score.originalAssetId].filter((id): id is string => Boolean(id))),
      ...next.originals.map((original) => original.assetId),
    ])];
    let bytes: number | null = 0;
    let volumes: number | null = 0;
    let metadataError = '';
    try {
      const metadata = await readPersonalAssetMetadata(ids);
      bytes = metadata.reduce((total, asset) => total + asset.size, 0);
      volumes = countPackedPersonalBackupVolumes(metadata);
    } catch (cause) {
      bytes = null;
      volumes = null;
      metadataError = cause instanceof Error ? cause.message : '无法检查附件备份限制';
    }
    if (!componentActive || generation !== reloadGeneration) return;
    data = next;
    migrationWarnings = getPersonalMigrationWarnings();
    backupAssetBytes = bytes;
    backupVolumeCount = volumes;
    backupAssetMetadataError = metadataError;
    loading = false;
  }
  onMount(() => {
    let active = true;
    componentActive = true;
    const unsubscribe = subscribePersonalData(() => { if (active) void reload().catch((cause) => { error = cause instanceof Error ? cause.message : String(cause); }); });
    const unsubscribeUpgrade = subscribePersonalStorageUpgrade((version) => { if (active) storageUpgrade = version; });
    void clearExpiredPersonalRestoreStages().catch(() => { /* cleanup is best-effort and never affects current data */ });
    void reload().catch((cause) => { error = cause instanceof Error ? cause.message : String(cause); loading = false; });
    return () => {
      active = false; componentActive = false; unsubscribe(); unsubscribeUpgrade(); volumePlan?.cancel(); operationAbort?.abort();
      if (volumePreview) void cancelPersonalBackupVolumesPreview(volumePreview).catch(() => { /* best-effort cleanup after leaving the page */ });
    };
  });

  function beginDownload(blob: Blob, fileName: string) {
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = fileName;
    document.body.append(anchor);
    anchor.click();
    anchor.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
  }

  async function exportBackup() {
    if (!data?.migrationCompleted || migrationWarnings.length) {
      error = '旧数据迁移尚未完整，当前不能生成“完整备份”。请检查迁移警告并重试。';
      return;
    }
    busy = true; error = ''; notice = '';
    try {
      const blob = await exportPersonalBackup();
      beginDownload(blob, `mimi-personal-${new Date().toISOString().slice(0, 10)}.json`);
      notice = `备份文件已生成（${(blob.size / 1024 / 1024).toFixed(2)} MiB），下载已发起。请确认文件出现在设备中。`;
    } catch (cause) { error = cause instanceof Error ? cause.message : String(cause); }
    finally { busy = false; }
  }

  async function retryMigration() {
    busy = true; error = ''; notice = '';
    try {
      migrationWarnings = await retryPersonalDataMigration();
      await reload();
      if (data?.migrationCompleted && migrationWarnings.length === 0) notice = '旧个人数据已迁移完成，现在可以导出完整备份。';
      else error = '仍有旧数据无法迁移；原始条目仍保留在浏览器旧存储中，完整备份继续停用。';
    } catch (cause) { error = cause instanceof Error ? cause.message : String(cause); }
    finally { busy = false; }
  }

  async function prepareRestore() {
    if (!file) return;
    busy = true; error = ''; notice = ''; preview = null;
    try { preview = await previewBackup(file); }
    catch (cause) { error = cause instanceof Error ? cause.message : String(cause); }
    finally { busy = false; }
  }

  async function applyRestore() {
    if (!preview) return;
    busy = true; error = ''; notice = '';
    try {
      await restoreBackup(preview, preview.expectedRevision);
      preview = null; file = null;
      notice = '备份校验和资料合并已提交到本设备。建议打开一份个人谱确认恢复内容。';
      await reload();
    } catch (cause) {
      error = cause instanceof Error ? cause.message : String(cause);
      notice = '恢复没有完成；当前资料保持可用。若提示预览已失效，请重新选择文件并预览。';
    } finally { busy = false; }
  }

  async function prepareVolumeBackup() {
    if (!data?.migrationCompleted || migrationWarnings.length) {
      error = '旧数据迁移尚未完整，当前不能生成完整备份。请先检查迁移警告。';
      return;
    }
    busy = true; volumeBackupBusy = true; error = ''; notice = ''; volumeProgress = '正在校验本机资料并准备分卷清单…';
    const controller = new AbortController();
    operationAbort = controller;
    volumePlan?.cancel(); volumePlan = null; readyVolume = null; readyVolumeSequence = 0; initiatedVolumes = []; manifestDownloadInitiated = false;
    try {
      const plan = await preparePersonalBackupVolumes(controller.signal);
      if (!componentActive || controller.signal.aborted) { plan.cancel(); return; }
      volumePlan = plan;
      volumeProgress = plan.volumeCount ? `清单已生成，正在准备第 1 / ${plan.volumeCount} 卷…` : '清单已生成；此备份没有附件分卷。';
      if (plan.volumeCount) {
        const firstVolume = await plan.createVolume(1, controller.signal);
        if (!componentActive || controller.signal.aborted) { plan.cancel(); return; }
        readyVolume = firstVolume;
        readyVolumeSequence = 1;
        volumeProgress = `第 1 / ${plan.volumeCount} 卷已准备。`;
      }
      notice = `v2 备份文件已准备：清单和 ${plan.volumeCount} 卷，共 ${(plan.totalFileBytes / 1024 / 1024).toFixed(2)} MiB。每个文件都要单独点击下载。`;
    } catch (cause) { if (componentActive) { error = cause instanceof Error ? cause.message : String(cause); volumePlan?.cancel(); volumePlan = null; readyVolume = null; } }
    finally { if (operationAbort === controller) operationAbort = null; if (componentActive) { busy = false; volumeBackupBusy = false; } }
  }

  function downloadVolumeManifest() {
    if (!volumePlan) return;
    const wasInitiated = manifestDownloadInitiated;
    beginDownload(volumePlan.manifest, volumePlan.manifestFileName);
    manifestDownloadInitiated = true;
    notice = wasInitiated
      ? '已再次发起清单下载；请在浏览器下载列表确认文件，应用无法确认最终保存。'
      : '清单下载已发起；请在浏览器下载列表确认文件，应用无法确认最终保存。';
  }

  function downloadPreparedVolume() {
    if (!volumePlan || !readyVolume || !readyVolumeSequence) return;
    const sequence = readyVolumeSequence;
    const wasInitiated = initiatedVolumes.includes(sequence);
    beginDownload(readyVolume, volumePlan.volumeFileName(readyVolumeSequence));
    if (!wasInitiated) initiatedVolumes = [...initiatedVolumes, sequence];
    notice = wasInitiated
      ? `已再次发起第 ${sequence} 卷下载；请在浏览器下载列表确认文件，应用无法确认最终保存。`
      : `第 ${sequence} 卷下载已发起；请在浏览器下载列表确认文件，应用无法确认最终保存。`;
  }

  async function prepareNextVolume() {
    if (!volumePlan || !readyVolume || !initiatedVolumes.includes(readyVolumeSequence) || readyVolumeSequence >= volumePlan.volumeCount) return;
    busy = true; volumeBackupBusy = true; error = ''; volumeProgress = `正在准备第 ${readyVolumeSequence + 1} / ${volumePlan.volumeCount} 卷…`;
    const plan = volumePlan;
    const controller = new AbortController();
    operationAbort = controller;
    try {
      const sequence = readyVolumeSequence + 1;
      const prepared = await plan.createVolume(sequence, controller.signal);
      if (!componentActive || controller.signal.aborted) { plan.cancel(); return; }
      readyVolume = prepared;
      readyVolumeSequence = sequence;
      volumeProgress = `第 ${sequence} / ${plan.volumeCount} 卷已准备。`;
    } catch (cause) { if (componentActive) { error = cause instanceof Error ? cause.message : String(cause); plan.cancel(); volumePlan = null; readyVolume = null; } }
    finally { if (operationAbort === controller) operationAbort = null; if (componentActive) { busy = false; volumeBackupBusy = false; } }
  }

  function cancelVolumePlan() {
    const volumeCount = volumePlan?.volumeCount ?? 0;
    const initiatedCount = initiatedVolumes.length;
    volumePlan?.cancel(); volumePlan = null; readyVolume = null; readyVolumeSequence = 0; initiatedVolumes = [];
    volumeBackupBusy = false;
    volumeProgress = initiatedCount
      ? `分卷计划已取消；${initiatedCount} / ${volumeCount} 卷曾发起下载，但无法据此确认已保存。`
      : '分卷下载计划已取消；此前没有发起卷下载。';
    operationAbort?.abort();
  }

  async function prepareVolumeRestore() {
    if (!volumeManifestFile) return;
    busy = true; error = ''; notice = ''; volumeProgress = '正在逐卷校验完整备份…';
    const oldPreview = volumePreview;
    const controller = new AbortController();
    operationAbort = controller;
    try {
      if (oldPreview) await cancelPersonalBackupVolumesPreview(oldPreview);
      if (componentActive && oldPreview && volumePreview === oldPreview) volumePreview = null;
      if (!componentActive || controller.signal.aborted) return;
      const manifestFile = volumeManifestFile;
      const selectedVolumes = [...volumeFiles];
      const checkedPreview = await previewPersonalBackupVolumes(manifestFile, selectedVolumes, controller.signal, (complete, total) => {
        if (componentActive && !controller.signal.aborted) volumeProgress = `正在校验第 ${complete} / ${total} 卷…`;
      });
      if (!componentActive || controller.signal.aborted) {
        await cancelPersonalBackupVolumesPreview(checkedPreview);
        return;
      }
      volumePreview = checkedPreview;
      volumeProgress = `全部 ${checkedPreview.volumeCount} 卷通过校验；缺失附件已写入临时数据，当前资料尚未更改。`;
    } catch (cause) {
      if (componentActive) {
        error = cause instanceof Error ? cause.message : String(cause);
        if (oldPreview && volumePreview === oldPreview) volumeProgress = '旧预览仍保留；若继续恢复，请先检查文件选择。';
      }
    } finally { if (operationAbort === controller) operationAbort = null; if (componentActive) busy = false; }
  }

  async function cancelVolumeRestorePreview() {
    const oldPreview = volumePreview;
    busy = true;
    error = '';
    try {
      if (oldPreview) await cancelPersonalBackupVolumesPreview(oldPreview);
      if (!componentActive) return;
      volumePreview = null;
      volumeManifestFile = null; volumeFiles = []; volumeProgress = '恢复预览已取消；本次临时数据已清理。';
    } catch (cause) {
      if (componentActive) error = `预览仍保留；本次临时数据未能确认清理：${cause instanceof Error ? cause.message : String(cause)}`;
    } finally { if (componentActive) busy = false; }
  }

  async function applyVolumeRestore() {
    if (!volumePreview) return;
    busy = true; error = ''; notice = '';
    const preview = volumePreview;
    const controller = new AbortController();
    operationAbort = controller;
    try {
      await restorePersonalBackupVolumes(preview, preview.expectedRevision, controller.signal);
      if (!componentActive) return;
      volumePreview = null; volumeManifestFile = null; volumeFiles = [];
      notice = 'v2 备份已完成版本校验，并合并保存到本设备。建议打开一份个人谱确认恢复内容。';
      volumeProgress = '';
      await reload();
    } catch (cause) {
      if (componentActive) {
        error = cause instanceof Error ? cause.message : String(cause);
        const cleanupFailed = error.includes('本次临时数据未能确认清理');
        volumePreview = cleanupFailed ? preview : null;
        volumeProgress = '恢复没有提交；当前资料保持可用。若提示临时数据未清理，请重新打开数据与备份页后重试；预览失效时请重新选择全部文件并校验。';
      }
    } finally { if (operationAbort === controller) operationAbort = null; if (componentActive) busy = false; }
  }

  async function replaceVolumeSelection(input: HTMLInputElement, update: () => void) {
    if (busy) return;
    busy = true;
    error = '';
    const oldPreview = volumePreview;
    try {
      if (oldPreview) await cancelPersonalBackupVolumesPreview(oldPreview);
      if (!componentActive) return;
      volumePreview = null;
      update();
      volumeProgress = '';
    } catch (cause) {
      if (componentActive) {
        input.value = '';
        error = `文件选择未更改；当前预览仍保留，因为本次临时数据未能确认清理：${cause instanceof Error ? cause.message : String(cause)}`;
      }
    } finally { if (componentActive) busy = false; }
  }

  const personalEntityCount = (value: PersonalDataSnapshot) => value.scores.length + value.favorites.length + value.practiceItems.length + (value.schemaVersion === 2 ? value.practiceFragments.length : 0) + value.resumes.length + value.sessions.length + value.projects.length + value.originals.length + value.history.length;
  const personalAssetCount = (value: PersonalDataSnapshot) => new Set([
    ...value.scores.flatMap((score) => [score.assetId, score.originalAssetId].filter((id): id is string => Boolean(id))),
    ...value.originals.map((original) => original.assetId),
  ]).size;
  const backupLimitWarning = (value: PersonalDataSnapshot) => {
    const entities = personalEntityCount(value);
    const assets = personalAssetCount(value);
    if (entities > MAX_PERSONAL_BACKUP_ENTITIES || assets > MAX_PERSONAL_BACKUP_ASSETS) return `现有资料超过可备份预算（${entities.toLocaleString()} / ${MAX_PERSONAL_BACKUP_ENTITIES.toLocaleString()} 个实体，${assets} / ${MAX_PERSONAL_BACKUP_ASSETS} 份引用附件）。系统会阻止继续增加超限资料；需要先整理，再生成完整备份。`;
    if (backupAssetMetadataError) return '无法检查附件的备份大小；为避免生成不完整备份，当前先暂停备份。请刷新页面后重试。';
    if (backupAssetBytes !== null && backupAssetBytes > MAX_PERSONAL_BACKUP_ASSET_BYTES) return `现有引用附件合计 ${(backupAssetBytes / 1024 / 1024).toFixed(2)} MiB，超过 ${MAX_PERSONAL_BACKUP_ASSET_BYTES / 1024 / 1024} MiB 备份预算；请先整理附件引用。`;
    if (backupVolumeCount !== null && backupVolumeCount > MAX_PERSONAL_BACKUP_VOLUMES) return `现有附件按分卷规则需要 ${backupVolumeCount} 卷，超过 ${MAX_PERSONAL_BACKUP_VOLUMES} 卷预算；请先整理附件引用。`;
    return '';
  };

  const countSummary = (value: PersonalDataSnapshot) => {
    const fragments = value.schemaVersion === 2 ? value.practiceFragments : [];
    const activeFragments = fragments.filter((fragment) => fragment.deletedAt === undefined).length;
    const deletedFragments = fragments.length - activeFragments;
    const fragmentCount = deletedFragments ? `${activeFragments} 个练习片段 · ${deletedFragments} 个已删除片段` : `${activeFragments} 个练习片段`;
    return `${value.scores.length} 份谱 · ${value.favorites.length} 个收藏 · ${value.practiceItems.length} 个待练 · ${fragmentCount} · ${value.sessions.length} 条练习记录 · ${value.projects.length} 个工程 · ${value.originals.length} 份原件`;
  };
</script>

<section class="personal-data-settings space-y-6">
  <div class="flex justify-end"><a href="/motion" class="inline-flex min-h-11 items-center rounded-full border border-[#e0d6c0] bg-[#fbf9f4] px-4 text-sm text-[#705c42] transition-colors hover:border-[#c49a45] hover:text-[#2d2926]">动效与交互偏好 →</a></div>
  {#if error}<p use:registerMotionSurface transition:fadeMotion={{ kind: 'notice' }} role="alert" class="rounded-xl border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800">{error}</p>{/if}
  {#if notice}<p use:registerMotionSurface transition:fadeMotion={{ kind: 'notice' }} role="status" class="rounded-xl border border-[#c49a45]/40 bg-[#c49a45]/10 px-4 py-3 text-sm text-[#70541e]">{notice}</p>{/if}
  {#if storageUpgrade}<div role="alert" class="rounded-xl border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-950"><p>个人资料库已由新版本升级（数据库版本 {storageUpgrade}）。请刷新此页后继续使用，旧页面已停止访问该库。</p><button type="button" class="btn btn-ghost mt-2" onclick={() => window.location.reload()}>刷新页面</button></div>{/if}
  {#if loading}<p class="card p-5 text-sm text-ash">正在读取本设备数据…</p>
  {:else if !data}<p class="card p-5 text-sm text-red-800">本地资料不可用，无法显示或备份。</p>
  {:else}
    <section class="card space-y-4 p-5 sm:p-6">
      <div><h2 class="font-display text-subheading">当前资料</h2><p class="mt-1 text-sm text-ash">修订号 {data.revision} · {countSummary(data)}</p></div>
      {#if backupLimitWarning(data)}<p role="alert" class="rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm text-amber-950">{backupLimitWarning(data)}</p>{/if}
      {#if !data.migrationCompleted || migrationWarnings.length}
        <div class="rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm text-amber-950" role="alert">
          <p class="font-semibold">旧数据迁移未完整，当前资料不代表完整备份</p>
          <p class="mt-1">仍有旧草稿或历史条目保留在旧浏览器存储中，完整备份已暂时停用。</p>
          {#if migrationWarnings.length}<ul class="mt-2 list-disc space-y-1 pl-5">{#each migrationWarnings as warning}<li>{warning}</li>{/each}</ul>{/if}
          <button type="button" class="btn btn-ghost mt-3" disabled={busy} onclick={retryMigration}>重试迁移</button>
        </div>
      {/if}
      <div class="flex flex-wrap gap-3"><button type="button" class="btn btn-signal" disabled={busy || !data.migrationCompleted || migrationWarnings.length > 0} onclick={exportBackup}>生成 v1 JSON 备份</button><a href="/library" class="btn btn-ghost">打开我的谱</a></div>
      <p class="text-xs leading-5 text-ash">v1 保持兼容，单个 JSON 文件最多 {Math.floor(MAX_PERSONAL_BACKUP_BYTES / 1024 / 1024)} MiB；适合小型备份。单附件最多 30 MiB、引用附件总量 927 MiB，附件最多 {MAX_PERSONAL_BACKUP_ASSETS} 份，资料实体最多 {MAX_PERSONAL_BACKUP_ENTITIES.toLocaleString()} 个。点击后只表示下载已发起，应用无法确认设备最终保存结果。</p>
    </section>

    <section class="card space-y-4 p-5 sm:p-6">
      <div><h2 class="font-display text-subheading">v2 长期分卷备份</h2><p class="mt-1 text-sm text-ash">清单 JSON 最多 {Math.floor(MAX_PERSONAL_BACKUP_MANIFEST_BYTES / 1024 / 1024)} MiB；附件按最多 {Math.floor(MAX_PERSONAL_BACKUP_VOLUME_BYTES / 1024 / 1024)} MiB 负载生成最多 {MAX_PERSONAL_BACKUP_VOLUMES} 个二进制卷。清单、卷头和全部卷的总文件大小最多 {Math.floor(MAX_PERSONAL_BACKUP_TOTAL_BYTES / 1024 / 1024)} MiB（1 GiB）；引用附件合计最多 927 MiB，为清单和卷头留出空间。单附件 30 MiB、引用附件 500 份、资料实体 10,000 个；设备空间可能低于格式上限。</p>
        {#if backupAssetBytes !== null && backupVolumeCount !== null}<p class="mt-1 text-xs text-ash">当前引用附件 {(backupAssetBytes / 1024 / 1024).toFixed(2)} / 927 MiB · 预计 {backupVolumeCount} / {MAX_PERSONAL_BACKUP_VOLUMES} 卷</p>{/if}
      </div>
      <button type="button" class="btn btn-signal" disabled={busy || !data.migrationCompleted || migrationWarnings.length > 0 || Boolean(backupLimitWarning(data))} onclick={prepareVolumeBackup}>准备 v2 分卷文件</button>
      {#if volumeBackupBusy}<button type="button" class="btn btn-ghost" onclick={cancelVolumePlan}>取消准备</button>{/if}
      {#if volumePlan}
        <div aria-busy={volumeBackupBusy} class="rounded-xl border border-[#c49a45]/40 bg-[#c49a45]/5 p-4 text-sm">
          <p class="font-semibold">此备份含 {volumePlan.volumeCount} 卷 · 总文件 {(volumePlan.totalFileBytes / 1024 / 1024).toFixed(2)} MiB</p>
          <p role="status" aria-live="polite" class="mt-1 text-ash">{volumeProgress} 每次只生成一卷；点击文件按钮才会发起下载，浏览器可能阻止连续下载。页面只保留当前已准备卷供重复下载；准备下一卷会替换当前卷，请先在浏览器下载列表确认并按需重下。发起下载不等于确认设备已保存。</p>
          <div class="mt-3 flex flex-wrap gap-3">
            <button type="button" class="btn btn-ghost min-h-11" disabled={busy} onclick={downloadVolumeManifest}>{manifestDownloadInitiated ? '再次下载 v2 清单' : '下载 v2 清单'}</button>
            {#if readyVolume}
              <button type="button" class="btn btn-ghost min-h-11" disabled={busy} onclick={downloadPreparedVolume}>{initiatedVolumes.includes(readyVolumeSequence) ? '再次下载' : '下载'}第 {readyVolumeSequence} / {volumePlan.volumeCount} 卷</button>
              {#if readyVolumeSequence < volumePlan.volumeCount && initiatedVolumes.includes(readyVolumeSequence)}
                <button type="button" class="btn btn-ghost min-h-11" disabled={busy} onclick={prepareNextVolume}>准备第 {readyVolumeSequence + 1} 卷</button>
              {/if}
            {:else if readyVolumeSequence < volumePlan.volumeCount && initiatedVolumes.includes(readyVolumeSequence)}
              <button type="button" class="btn btn-ghost min-h-11" disabled={busy} onclick={prepareNextVolume}>准备第 {readyVolumeSequence + 1} 卷</button>
            {/if}
            <button type="button" class="btn btn-ghost min-h-11" disabled={busy} onclick={cancelVolumePlan}>取消计划</button>
          </div>
          <p class="mt-2 text-xs text-ash">已发起卷下载：{initiatedVolumes.length} / {volumePlan.volumeCount}。这不是设备保存确认。1 GiB 是格式硬上限，尚未在本机对完整 1 GiB 数据做实测。</p>
        </div>
      {:else if volumeProgress}
        <p role="status" class="text-sm text-ash">{volumeProgress}</p>
      {/if}
    </section>

    <section class="card space-y-4 p-5 sm:p-6">
      <div><h2 class="font-display text-subheading">校验并恢复 v1 JSON</h2><p class="mt-1 text-sm text-ash">选择之前生成的完整 v1 文件。预览会校验摘要和附件；恢复以当前数据为基础合并，并保留冲突副本。</p></div>
      <div class="flex flex-wrap gap-3"><input type="file" accept="application/json,.json" aria-label="选择个人资料备份" disabled={busy} onchange={(event) => { file = event.currentTarget.files?.[0] ?? null; preview = null; error = ''; }} /><button type="button" class="btn btn-ghost" disabled={busy || !file} onclick={prepareRestore}>校验并预览</button></div>
      {#if preview}
        <div class="rounded-xl border border-[#c49a45]/40 bg-[#c49a45]/5 p-4 text-sm">
          <p class="font-semibold">备份已通过完整性校验</p>
          <p class="mt-1 text-ash">版本 {preview.manifest.formatVersion} · {new Date(preview.manifest.generatedAt).toLocaleString()} · {(preview.fileSize / 1024 / 1024).toFixed(2)} MiB</p>
          <p class="mt-1 text-ash">{countSummary(preview.data)} · 附件 {preview.assets.length} 份</p>
          <button type="button" class="btn btn-signal mt-4" disabled={busy} onclick={applyRestore}>合并并恢复此备份</button>
        </div>
      {/if}
    </section>

    <section class="card space-y-4 p-5 sm:p-6">
      <div><h2 class="font-display text-subheading">校验并恢复 v2 分卷</h2><p class="mt-1 text-sm text-ash">选择一个 v2 JSON 清单和同一份备份的全部二进制卷。全部卷通过序号、备份版本、长度和 SHA-256 校验后才会出现恢复预览；缺卷、混入其他备份或取消都会清理本次临时数据，不触碰当前资料。</p></div>
      <label class="block text-sm">v2 清单 JSON<input class="mt-2 block w-full" type="file" accept="application/json,.json" aria-label="选择 v2 备份清单" disabled={busy} onchange={(event) => { const input = event.currentTarget; const nextFile = input.files?.[0] ?? null; void replaceVolumeSelection(input, () => { volumeManifestFile = nextFile; }); }} /></label>
      <label class="block text-sm">二进制分卷（可多选，文件顺序不限）<input class="mt-2 block w-full" type="file" multiple accept=".mibak2,application/octet-stream" aria-label="选择 v2 备份分卷" disabled={busy} onchange={(event) => { const input = event.currentTarget; const nextFiles = [...(input.files ?? [])]; void replaceVolumeSelection(input, () => { volumeFiles = nextFiles; }); }} /></label>
      <div class="flex flex-wrap gap-3"><button type="button" class="btn btn-ghost" disabled={busy || !volumeManifestFile} onclick={prepareVolumeRestore}>校验全部分卷</button>{#if busy && operationAbort}<button type="button" class="btn btn-ghost" onclick={() => operationAbort?.abort()}>取消当前操作</button>{/if}</div>
      {#if volumeProgress}<p role="status" class="text-sm text-ash">{volumeProgress}</p>{/if}
      {#if volumePreview}
        <div class="rounded-xl border border-[#c49a45]/40 bg-[#c49a45]/5 p-4 text-sm">
          <p class="font-semibold">v2 备份完整性校验通过</p>
          <p class="mt-1 text-ash">{new Date(volumePreview.manifest.generatedAt).toLocaleString()} · {volumePreview.volumeCount} 卷 · {(volumePreview.fileSize / 1024 / 1024).toFixed(2)} MiB · 附件 {volumePreview.assetCount} 份（{(volumePreview.assetBytes / 1024 / 1024).toFixed(2)} MiB）</p>
          <p class="mt-1 text-ash">{countSummary(volumePreview.data)}。缺失附件已写入临时数据；当前资料尚未改变。</p>
          <div class="mt-4 flex flex-wrap gap-3"><button type="button" class="btn btn-signal" disabled={busy} onclick={applyVolumeRestore}>合并并恢复此备份</button><button type="button" class="btn btn-ghost" disabled={busy} onclick={cancelVolumeRestorePreview}>取消预览并清理临时数据</button></div>
        </div>
      {/if}
    </section>
  {/if}
</section>

<style>
  :global(.personal-data-settings a) {
    min-height: 44px;
  }

  :global(.personal-data-settings button),
  :global(.personal-data-settings select),
  :global(.personal-data-settings input) {
    min-height: 44px;
  }
</style>
