<script lang="ts">
  import MotionSegmentedControl from './ui/MotionSegmentedControl.svelte';
  import { registerMotionSurface, surfaceMotion } from '../lib/ui/motion.ts';

  const choices = [
    { value: 'warmup', label: '热身' },
    { value: 'segment', label: '分段' },
    { value: 'review', label: '回顾' },
  ];
  const views: Record<string, { index: string; title: string; body: string; mark: string }> = {
    warmup: { index: '01', title: '先找回手指的节奏。', body: '从舒适的速度开始，让每一次拨弦都清楚、均匀。', mark: '慢速 · 放松 · 均匀' },
    segment: { index: '02', title: '把困难留在一小段。', body: '选好 A-B，放慢难点，再用小步提速接近目标。', mark: '选段 · 循环 · 提速' },
    review: { index: '03', title: '听见一点点进步。', body: '记下这次的感受，下次从熟悉的位置继续。', mark: '记录 · 回看 · 继续' },
  };
  let selected = $state('warmup');
  let expanded = $state(false);
  let gradual = $state(true);
  let bpm = $state(60);
  const view = $derived(views[selected] ?? views.warmup);

  function openSearch() {
    window.dispatchEvent(new Event('open-command-palette'));
  }
</script>

<section class="experience" aria-labelledby="experience-title">
  <div class="experience__heading">
    <div>
      <p class="experience__eyebrow">一页安静的练习桌</p>
      <h2 id="experience-title">选择、调整，然后继续。</h2>
    </div>
    <span class="experience__badge"><span aria-hidden="true"></span>交互预览</span>
  </div>

  <div class="experience__grid">
    <aside class="experience__aside">
      <div class="experience__illustration" aria-hidden="true">
        <svg viewBox="0 0 180 200" fill="none">
          <path d="M48 174L76 34h28l28 140H48Z" fill="#ebe1cf" stroke="#c2ad8d" />
          <path d="M56 164L80 46h20l24 118H56Z" fill="#faf5eb" stroke="#d8cab4" />
          <path d="M87 154l18-107" stroke="#725c3b" stroke-width="3" stroke-linecap="round" />
          <rect x="94" y="75" width="15" height="24" rx="3" fill="#9c7743" transform="rotate(10 94 75)" />
          <circle cx="87" cy="154" r="7" fill="#755c37" />
          <path d="M70 179h40" stroke="#755c37" stroke-width="4" stroke-linecap="round" />
          <path d="M78 66h12m-15 17h12m-15 17h12m-15 17h12m-15 17h12" stroke="#d4c5ac" stroke-width="2" />
        </svg>
      </div>
      <p class="experience__aside-title">不着急，慢慢来。</p>
      <p class="experience__aside-copy">每一次细小调整，<br />都是下一次进步的开始。</p>
      <button type="button" class="experience__search" onclick={openSearch}>试试快捷搜索 <span aria-hidden="true">↗</span></button>
    </aside>

    <div class="experience__workspace">
      <MotionSegmentedControl value={selected} options={choices} onChange={(value) => selected = value} label="练习视图预览" />

      <div class="experience__view" aria-live="polite" aria-atomic="true">
        {#key selected}
          <div use:registerMotionSurface in:surfaceMotion={{ kind: 'panel', y: 8 }}>
            <p class="experience__number">{view.index} <span>/ DAILY PRACTICE</span></p>
            <h3>{view.title}</h3>
            <p class="experience__body">{view.body}</p>
            <p class="experience__mark">{view.mark}</p>
          </div>
        {/key}
      </div>

      <div class="experience__settings">
        <button type="button" class="experience__disclosure" aria-expanded={expanded} aria-controls="experience-settings" onclick={() => expanded = !expanded}>
          <span><strong>练习设置</strong><small>调整节奏，保留你的步调</small></span>
          <svg class:rotated={expanded} viewBox="0 0 20 20" width="20" height="20" fill="none" aria-hidden="true"><path d="m6 8 4 4 4-4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" /></svg>
        </button>
        <div id="experience-settings" inert={!expanded} aria-hidden={!expanded}>
        {#if expanded}
          <div class="experience__settings-body" use:registerMotionSurface transition:surfaceMotion={{ kind: 'panel', y: 6 }}>
            <label class="experience__tempo" for="experience-tempo"><span>起步速度</span><output for="experience-tempo">{bpm} <small>BPM</small></output></label>
            <input id="experience-tempo" class="experience__range" type="range" min="40" max="120" step="5" bind:value={bpm} />
            <label class="experience__switch-row" for="experience-gradual">
              <span><strong>逐步提速</strong><small>{gradual ? '每次前进一小步' : '先保持舒适的速度'}</small></span>
              <span class="experience__switch"><input id="experience-gradual" type="checkbox" role="switch" bind:checked={gradual} /><span aria-hidden="true"></span></span>
            </label>
          </div>
        {/if}
        </div>
      </div>

      <div class="experience__actions"><span>准备好了，就开始吧。</span><a class="btn btn-primary min-h-[44px]" href="/practice">打开我的练习 <span aria-hidden="true">→</span></a></div>
    </div>
  </div>
</section>

<style>
  .experience { overflow: hidden; border: 1px solid #e1d6c5; border-radius: 28px; background: #fffdf8; box-shadow: 0 2px 3px #6d4d2010, 0 18px 60px -30px #6d4d2026; }
  .experience__heading { display: flex; justify-content: space-between; align-items: center; gap: 16px; padding: 26px 32px; border-bottom: 1px solid #eee6d9; }
  .experience__eyebrow { margin-bottom: 6px; font-size: 11px; letter-spacing: 0.08em; color: #948269; }
  h2 { font-size: 16px; font-weight: 500; }
  .experience__badge { display: inline-flex; align-items: center; gap: 6px; white-space: nowrap; font-size: 11px; color: #887655; }
  .experience__badge > span { width: 5px; height: 5px; border-radius: 50%; background: #a68a5d; }
  .experience__grid { display: grid; grid-template-columns: minmax(180px, 0.65fr) minmax(0, 1.35fr); }
  .experience__aside { display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 32px 24px; text-align: center; background: linear-gradient(140deg, #f2ebdd, #faf5ea); border-right: 1px solid #e9dfcd; }
  .experience__illustration { width: 154px; margin: 0 auto 10px; }
  .experience__aside-title { font-family: var(--font-serif); font-size: 17px; color: #68543b; }
  .experience__aside-copy { margin-top: 12px; font-size: 12px; line-height: 1.9; color: #99866a; }
  .experience__search { display: inline-flex; align-items: center; justify-content: center; gap: 16px; min-height: 44px; margin-top: 24px; padding: 0 12px; font-size: 12px; color: #725c3b; border-radius: 12px; transition: background-color var(--motion-duration-micro) ease; }
  .experience__search:hover { background-color: #e8decf; }
  .experience__workspace { min-width: 0; padding: 28px 32px; }
  .experience__view { min-height: 230px; padding: 30px 2px 22px; }
  .experience__number { font-family: var(--font-display); font-size: 26px; color: #a48a62; }
  .experience__number > span { margin-left: 8px; font-family: var(--font-sans); font-size: 9px; letter-spacing: 0.15em; color: #a79984; }
  h3 { margin-top: 12px; font-size: clamp(18px, 2vw, 26px); font-weight: 500; line-height: 1.5; }
  .experience__body { margin-top: 10px; font-size: 13px; line-height: 1.85; color: #887960; }
  .experience__mark { margin-top: 20px; font-size: 11px; color: #9a8058; letter-spacing: 0.08em; }
  .experience__settings { overflow: hidden; border: 1px solid #e8dfd1; border-radius: 16px; background: #fcf9f3; }
  .experience__disclosure { display: flex; justify-content: space-between; align-items: center; width: 100%; min-height: 68px; padding: 14px 18px; text-align: left; }
  .experience__disclosure strong, .experience__switch-row strong { display: block; font-size: 13px; font-weight: 500; color: #665740; }
  .experience__disclosure small, .experience__switch-row small { display: block; margin-top: 4px; font-size: 11px; color: #9d8b71; }
  .experience__disclosure svg { flex-shrink: 0; color: #9a8769; transition: transform var(--motion-duration-control) var(--motion-ease-settle); }
  .experience__disclosure .rotated { transform: rotate(180deg); }
  .experience__settings-body { padding: 4px 18px 18px; }
  .experience__tempo { display: flex; justify-content: space-between; align-items: baseline; font-size: 12px; color: #827052; }
  .experience__tempo output { font-family: var(--font-display); font-size: 24px; color: #57462f; }
  .experience__tempo small { font-family: var(--font-sans); font-size: 10px; color: #a18c6b; }
  .experience__range { display: block; width: 100%; height: 44px; margin: 0; accent-color: #9c7743; }
  .experience__switch-row { display: flex; justify-content: space-between; align-items: center; gap: 12px; min-height: 60px; padding-top: 8px; border-top: 1px solid #e9dfd0; cursor: pointer; }
  .experience__switch { position: relative; display: inline-grid; align-items: center; width: 52px; height: 44px; flex-shrink: 0; }
  .experience__switch input { position: absolute; inset: 0; width: 100%; height: 100%; margin: 0; opacity: 0; cursor: pointer; z-index: 1; }
  .experience__switch > span { display: block; width: 48px; height: 28px; padding: 3px; border-radius: 28px; background: #d8cfbf; transition: background-color var(--motion-duration-control) ease; }
  .experience__switch > span::after { content: ''; display: block; width: 22px; height: 22px; border-radius: 50%; background: #fffdf8; box-shadow: 0 1px 3px #493c2a26; transition: transform var(--motion-duration-control) var(--motion-ease-settle); }
  .experience__switch input:checked + span { background: #9a7746; }
  .experience__switch input:checked + span::after { transform: translateX(20px); }
  .experience__switch input:focus-visible + span { outline: 2px solid var(--color-signal); outline-offset: 3px; }
  .experience__actions { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 12px; margin-top: 24px; }
  .experience__actions > span { font-size: 11px; color: #9a8970; }
  @media (max-width: 639px) {
    .experience { border-radius: 22px; }
    .experience__heading { padding: 20px; align-items: flex-start; }
    .experience__grid { grid-template-columns: minmax(0, 1fr); }
    .experience__aside { display: none; }
    .experience__workspace { padding: 20px; }
    .experience__view { min-height: 245px; }
    .experience__actions > a { width: 100%; }
  }
  @media (prefers-reduced-motion: reduce) {
    .experience__disclosure svg, .experience__switch > span, .experience__switch > span::after { transition: none; }
  }
</style>
