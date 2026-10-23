<script lang="ts">
  import { onMount } from 'svelte';
  import {
    getMotionPreferenceSnapshot,
    setMotionPreference,
    subscribeMotionPreference,
    type MotionPreference,
    type MotionPreferenceSnapshot,
  } from '../../lib/ui/motionPreferences.ts';
  import MotionSegmentedControl, { type MotionSegmentOption } from './MotionSegmentedControl.svelte';

  const options: MotionSegmentOption[] = [
    { value: 'system', label: '跟随系统' },
    { value: 'gentle', label: '轻柔' },
    { value: 'off', label: '静止' },
  ];

  let snapshot = $state.raw<MotionPreferenceSnapshot>(getMotionPreferenceSnapshot());
  let hydrated = $state(false);

  onMount(() => {
    const unsubscribe = subscribeMotionPreference((value) => {
      snapshot = value;
      hydrated = true;
    });
    return unsubscribe;
  });

  function choosePreference(value: string) {
    if (value === 'system' || value === 'gentle' || value === 'off') {
      setMotionPreference(value as MotionPreference);
    }
  }

  const selectedDescription = $derived.by(() => {
    if (snapshot.preference === 'gentle') return '使用短淡入，不做位移、倾斜或背景运动。';
    if (snapshot.preference === 'off') return '界面状态直接到达终态，不播放装饰动效。';
    return '跟随设备设置：系统未要求减少动态时使用完整效果，系统开启减少动态效果时自动静止。';
  });

  const effectiveDescription = $derived.by(() => {
    if (!hydrated) return '正在读取设备的动效设置…';
    if (snapshot.systemReducedMotion === true) return '设备系统减少动态效果已启用，当前实际效果为静止。';
    if (snapshot.systemReducedMotion === null) return '无法读取设备的动效设置，当前按静止效果处理。';
    if (snapshot.mode === 'gentle') return '当前实际效果：轻柔。';
    if (snapshot.mode === 'off') return '当前实际效果：静止。';
    return '当前实际效果：完整。';
  });

  const persistenceDescription = $derived.by(() => {
    if (!hydrated) return '动效偏好仅保存在当前浏览器，不纳入个人数据备份。';
    if (snapshot.persistence === 'session-only') return '当前设置已在本页生效，但浏览器未能保存；刷新后本次选择可能丢失。';
    if (snapshot.hasStoredPreference) return '偏好已保存在当前浏览器，不纳入个人数据备份。';
    return '尚未保存个人选择；当前使用系统默认。更改后会保存在当前浏览器。';
  });
</script>

<section class="motion-preferences" aria-labelledby="motion-preferences-title">
  <div class="motion-preferences__copy">
    <p class="motion-preferences__eyebrow">阅读与操作偏好</p>
    <h2 id="motion-preferences-title">动效</h2>
    <p class="motion-preferences__description">{selectedDescription}</p>
  </div>

  <MotionSegmentedControl
    value={snapshot.preference}
    {options}
    onChange={choosePreference}
    label="全站动效偏好"
    id="motion-preference-control"
  />

  <div class="motion-preferences__status" aria-live="polite" aria-atomic="true">
    <p>{effectiveDescription}</p>
    <p>{persistenceDescription}</p>
  </div>
  <p class="motion-preferences__system-note">设备系统的“减少动态效果”设置始终优先生效，手动选择也不会覆盖它。</p>
</section>

<style>
  .motion-preferences {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    align-items: center;
    gap: 18px 24px;
    padding: 22px;
    border: 1px solid #e3d9c8;
    border-radius: 18px;
    background: #fffdf8;
    box-shadow: 0 8px 28px -22px rgb(73 57 32 / 30%);
  }

  .motion-preferences__copy { min-width: 0; }
  .motion-preferences__eyebrow { margin-bottom: 4px; color: #948269; font-size: 10px; letter-spacing: 0.1em; }
  h2 { margin: 0; color: #3d3428; font-size: 18px; font-weight: 550; }
  .motion-preferences__description { margin-top: 6px; color: #81735e; font-size: 12px; line-height: 1.7; }
  .motion-preferences__status { grid-column: 1 / -1; display: grid; gap: 3px; padding-top: 12px; border-top: 1px solid #eee7dc; color: #756851; font-size: 11px; line-height: 1.7; }
  .motion-preferences__system-note { grid-column: 1 / -1; color: #9a8669; font-size: 10px; line-height: 1.6; }

  @media (max-width: 620px) {
    .motion-preferences { grid-template-columns: minmax(0, 1fr); gap: 14px; padding: 18px; }
    .motion-preferences :global(.motion-segmented-control) { width: 100%; }
  }
</style>
