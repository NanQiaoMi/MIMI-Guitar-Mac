<script lang="ts">
  import CodeBlock from './CodeBlock.svelte';

  // State: Audio Waveform Equalizer
  let isPlaying = $state(true);
  let playbackTempo = $state(1.0);
  let waveformMode = $state<'dynamic' | 'calm' | 'energetic' | 'mute'>('dynamic');

  // State: System Status
  let systemStatus = $state<'operational' | 'degraded' | 'maintenance'>('operational');

  // State: Newsletter Subscription
  let subscribeEmail = $state('');
  let isSubscribed = $state(false);
  let isSubmitting = $state(false);

  let activeTab = $state<'preview' | 'code' | 'tokens'>('preview');

  function handleSubscribe(e: SubmitEvent) {
    e.preventDefault();
    if (!subscribeEmail || isSubmitting) return;
    isSubmitting = true;
    setTimeout(() => {
      isSubmitting = false;
      isSubscribed = true;
      setTimeout(() => {
        isSubscribed = false;
        subscribeEmail = '';
      }, 3500);
    }, 600);
  }

  // Generate 18 dynamic waveform bar heights
  const barHeights = [14, 22, 18, 28, 34, 26, 16, 30, 36, 24, 18, 32, 28, 20, 34, 22, 16, 12];

  const statusMap = {
    operational: { label: 'Service Operational · 全部服务正常', color: '#22c55e', bg: 'bg-[#22c55e]', ring: 'rgba(34, 197, 94, 0.4)' },
    degraded: { label: 'Degraded Performance · 音频引擎微延迟', color: '#eab308', bg: 'bg-[#eab308]', ring: 'rgba(234, 179, 8, 0.4)' },
    maintenance: { label: 'Scheduled Maintenance · 系统例行升级', color: '#e7000b', bg: 'bg-[#e7000b]', ring: 'rgba(231, 0, 11, 0.4)' },
  };

  const currentStatus = $derived(statusMap[systemStatus]);

  const snippetCode = `<!-- 现代工程风 Mega Footer (Audio Waveform & Operational Pulse) -->
<footer class="border-t border-[#e5e5e5] bg-[#fafafa]">
  <!-- 顶部音频波形频谱与状态条 -->
  <div class="border-b border-[#e5e5e5] px-6 py-4">
    <div class="mx-auto flex max-w-[1200px] items-center justify-between">
      <!-- 动态音频波形微动条 -->
      <div class="flex items-end gap-1 h-7">
        {#each bars as h, i}
          <span 
            class="wave-bar" 
            style="animation-duration: \${1.2 / tempo}s; animation-delay: \${i * 0.1}s; height: \${h}px;" 
          />
        {/each}
      </div>

      <!-- 实时服务健康指示灯 -->
      <div class="inline-flex items-center gap-2 rounded-[18px] border border-[#e5e5e5] bg-white px-3 py-1 text-xs">
        <span class="status-pulse" />
        <span class="font-mono text-[#0a0a0a]">Service Operational</span>
      </div>
    </div>
  </div>

  <!-- 4 列精细发丝网格分栏 -->
  <div class="mx-auto max-w-[1200px] grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-8 p-12">
    <!-- Links with subtle drift hover -->
  </div>
</footer>`;

  const tokensSpec = `/* Refero UI Mega Footer Tokens */
--footer-border: 1px solid var(--color-hairline);
--wave-bar-width: 3px;
--wave-bar-radius: 2px;
--status-pulse-color: #22c55e;
--footer-link-drift: 2px;`;
</script>

<div class="space-y-8">
  <!-- Sub-Header & Switcher -->
  <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between border-b border-[#e5e5e5] pb-5">
    <div>
      <div class="inline-flex items-center gap-2 rounded-[18px] border border-[#e5e5e5] bg-[#fafafa] px-3 py-1 text-xs font-medium text-[#737373]">
        <span class="h-2 w-2 rounded-full bg-[#22c55e]"></span>
        MODULE 06 · 声学波形与工程页脚
      </div>
      <h2 class="mt-2 font-display text-2xl text-[#0a0a0a]">Mega Footer 现代工程页脚 (Waveform & Operational Pulse)</h2>
      <p class="mt-1 text-sm text-[#737373]">
        音频均衡器声波律动、Service Operational 呼吸微脉冲、发丝分栏网格与微位移超链接。
      </p>
    </div>

    <!-- View Switcher Tabs -->
    <div class="flex items-center rounded-[18px] border border-[#e5e5e5] bg-[#f5f5f5] p-1 text-xs font-medium">
      <button
        type="button"
        onclick={() => (activeTab = 'preview')}
        class="rounded-[14px] px-3 py-1.5 transition-all {activeTab === 'preview' ? 'bg-white text-[#0a0a0a] shadow-xs' : 'text-[#737373] hover:text-[#0a0a0a]'}"
      >
        🌟 交互演示
      </button>
      <button
        type="button"
        onclick={() => (activeTab = 'code')}
        class="rounded-[14px] px-3 py-1.5 transition-all {activeTab === 'code' ? 'bg-white text-[#0a0a0a] shadow-xs' : 'text-[#737373] hover:text-[#0a0a0a]'}"
      >
        💻 示例源码
      </button>
      <button
        type="button"
        onclick={() => (activeTab = 'tokens')}
        class="rounded-[14px] px-3 py-1.5 transition-all {activeTab === 'tokens' ? 'bg-white text-[#0a0a0a] shadow-xs' : 'text-[#737373] hover:text-[#0a0a0a]'}"
      >
        📐 Token 规范
      </button>
    </div>
  </div>

  {#if activeTab === 'preview'}
    <div class="space-y-6">
      <!-- MAIN MEGA FOOTER LIVE PREVIEW CONTAINER -->
      <div class="overflow-hidden rounded-[24px] border border-[#e5e5e5] bg-white shadow-xs">
        <!-- Top Waveform Bar & Operational Status Header -->
        <div class="flex flex-wrap items-center justify-between gap-4 border-b border-[#e5e5e5] bg-[#fafafa] px-6 sm:px-8 py-4">
          <!-- Live Audio Waveform Equalizer -->
          <div class="flex items-center gap-3">
            <button
              type="button"
              onclick={() => (isPlaying = !isPlaying)}
              class="flex h-8 w-8 items-center justify-center rounded-[10px] border border-[#e5e5e5] bg-white text-xs text-[#0a0a0a] shadow-xs transition hover:bg-[#f5f5f5]"
              title={isPlaying ? '暂停律动' : '恢复律动'}
            >
              {#if isPlaying}
                <span>⏸</span>
              {:else}
                <span>▶</span>
              {/if}
            </button>

            <!-- Waveform Bars -->
            <div class="flex items-end gap-1 h-7 px-1">
              {#each barHeights as h, idx}
                <span
                  class="w-[3px] rounded-full transition-all"
                  style="
                    height: {waveformMode === 'mute' ? '4px' : `${h}px`};
                    background-color: {isPlaying ? '#0a0a0a' : '#dee2de'};
                    animation: {isPlaying && waveformMode !== 'mute' ? `wave-bounce ${1.2 / playbackTempo}s ease-in-out infinite` : 'none'};
                    animation-delay: {idx * 0.08}s;
                  "
                ></span>
              {/each}
            </div>

            <span class="font-mono text-xs text-[#737373] hidden sm:inline-block">
              WebAudio 44.1kHz · {playbackTempo}x
            </span>
          </div>

          <!-- Service Operational Status Indicator -->
          <div class="inline-flex items-center gap-2 rounded-[18px] border border-[#e5e5e5] bg-white px-3 py-1.5 text-xs font-medium text-[#0a0a0a] shadow-xs">
            <span
              class="h-2.5 w-2.5 rounded-full animate-pulse"
              style="
                background-color: {currentStatus.color};
                box-shadow: 0 0 0 4px {currentStatus.ring};
              "
            ></span>
            <span class="font-mono">{currentStatus.label}</span>
          </div>
        </div>

        <!-- Mega Footer Main 4-Column Content -->
        <div class="p-8 sm:p-12 space-y-12">
          <div class="flex flex-col md:flex-row md:items-center justify-between gap-6 border-b border-[#e5e5e5] pb-8">
            <div>
              <h3 class="font-display text-2xl sm:text-3xl text-[#0a0a0a] tracking-tight">
                把每一份乐谱，都当作一页书来对待
              </h3>
              <p class="mt-1 text-xs sm:text-sm text-[#737373]">
                开源吉他乐谱解析引擎 · 现代乐手与吉他教师的数字化工作台
              </p>
            </div>

            <!-- Newsletter Subscription Pill -->
            <form onsubmit={handleSubscribe} class="relative flex w-full max-w-sm items-center">
              <input
                type="email"
                required
                placeholder="输入邮箱订阅每周精选谱单..."
                bind:value={subscribeEmail}
                class="w-full rounded-[18px] border border-[#e5e5e5] bg-[#fafafa] px-4 py-2.5 pr-24 text-xs text-[#0a0a0a] outline-none transition focus:border-[#0a0a0a] focus:bg-white"
              />
              <button
                type="submit"
                disabled={isSubmitting || isSubscribed}
                class="absolute right-1.5 top-1/2 -translate-y-1/2 rounded-[14px] bg-[#0a0a0a] px-3 py-1.5 text-xs font-medium text-white transition hover:bg-[#2c2c2c] active:scale-95 disabled:opacity-70"
              >
                {#if isSubmitting}
                  <span class="inline-block animate-spin">⏳</span>
                {:else if isSubscribed}
                  <span>✓ 已订阅</span>
                {:else}
                  <span>订阅</span>
                {/if}
              </button>
            </form>
          </div>

          <!-- 4-Column Links Grid with Drift Interaction -->
          <div class="grid grid-cols-1 gap-8 sm:grid-cols-2 lg:grid-cols-4 text-xs">
            <div>
              <h4 class="text-caption tracking-[0.2em] uppercase text-[#a3a3a3] mb-4 font-mono">了解 MIMI GUITAR</h4>
              <ul class="space-y-2.5 text-[#444141]">
                <li><a href="#about" class="inline-block transition-transform duration-200 hover:translate-x-1.5 hover:text-[#0a0a0a]">关于我们与初心</a></li>
                <li><a href="#help" class="inline-block transition-transform duration-200 hover:translate-x-1.5 hover:text-[#0a0a0a]">乐谱阅读与排版指南</a></li>
                <li><a href="#contact" class="inline-block transition-transform duration-200 hover:translate-x-1.5 hover:text-[#0a0a0a]">制谱师认证通道</a></li>
                <li><a href="#feedback" class="inline-block transition-transform duration-200 hover:translate-x-1.5 hover:text-[#0a0a0a]">功能反馈与建议</a></li>
              </ul>
            </div>

            <div>
              <h4 class="text-caption tracking-[0.2em] uppercase text-[#a3a3a3] mb-4 font-mono">核心曲库分流</h4>
              <ul class="space-y-2.5 text-[#444141]">
                <li><a href="#guitar" class="inline-block transition-transform duration-200 hover:translate-x-1.5 hover:text-[#0a0a0a]">🎸 吉他原声指弹曲库</a></li>
                <li><a href="#ukulele" class="inline-block transition-transform duration-200 hover:translate-x-1.5 hover:text-[#0a0a0a]">🌴 尤克里里独奏/弹唱</a></li>
                <li><a href="#electric" class="inline-block transition-transform duration-200 hover:translate-x-1.5 hover:text-[#0a0a0a]">⚡ 电吉他 Solo 与重金属</a></li>
                <li><a href="#articles" class="inline-block transition-transform duration-200 hover:translate-x-1.5 hover:text-[#0a0a0a]">📖 吉他乐理与大师专栏</a></li>
              </ul>
            </div>

            <div>
              <h4 class="text-caption tracking-[0.2em] uppercase text-[#a3a3a3] mb-4 font-mono">开源协议与版权</h4>
              <ul class="space-y-2.5 text-[#444141]">
                <li><a href="#copyright" class="inline-block transition-transform duration-200 hover:translate-x-1.5 hover:text-[#0a0a0a]">版权声明与投诉规范</a></li>
                <li><a href="#agreement" class="inline-block transition-transform duration-200 hover:translate-x-1.5 hover:text-[#0a0a0a]">用户服务使用协议</a></li>
                <li><a href="#privacy" class="inline-block transition-transform duration-200 hover:translate-x-1.5 hover:text-[#0a0a0a]">隐私安全保护政策</a></li>
                <li><a href="#uploadpolicy" class="inline-block transition-transform duration-200 hover:translate-x-1.5 hover:text-[#0a0a0a]">创作者上传分成准则</a></li>
              </ul>
            </div>

            <div>
              <h4 class="text-caption tracking-[0.2em] uppercase text-[#a3a3a3] mb-4 font-mono">技术架构与规范</h4>
              <div class="rounded-[18px] border border-[#e5e5e5] bg-[#fafafa] p-3 space-y-2">
                <div class="flex items-center justify-between">
                  <span class="text-[#737373]">渲染引擎:</span>
                  <span class="font-mono text-[#0a0a0a]">AlphaTab v1.8.4</span>
                </div>
                <div class="flex items-center justify-between">
                  <span class="text-[#737373]">前端框架:</span>
                  <span class="font-mono text-[#0a0a0a]">Astro 5 + Svelte 5</span>
                </div>
                <div class="flex items-center justify-between">
                  <span class="text-[#737373]">设计规范:</span>
                  <span class="font-mono text-[#0a0a0a]">Refero UI · 18/24px</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Bottom Legal & ICP Bar -->
          <div class="border-t border-[#e5e5e5] pt-6 flex flex-col sm:flex-row sm:items-center justify-between gap-3 text-caption text-[#a3a3a3]">
            <p>© 2026 MIMI Guitar · 学习演示与现代吉他曲谱数字化工程</p>
            <p class="font-mono text-[11px]">粤ICP备XXXXXXXX号 · 网络文化经营许可证：占位</p>
          </div>
        </div>
      </div>

      <!-- Controls Panel for Footer -->
      <div class="rounded-[24px] border border-[#e5e5e5] bg-white p-5 shadow-xs">
        <h3 class="font-display text-base text-[#0a0a0a]">🎛️ 页脚声波与运行状态调谐</h3>
        <div class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-3 text-xs">
          <!-- Tempo Multiplier -->
          <div>
            <span class="font-medium text-[#444141]">波形律动节奏速度</span>
            <div class="mt-2 flex items-center gap-1.5">
              {#each [0.5, 1.0, 1.5, 2.0] as t}
                <button
                  type="button"
                  onclick={() => (playbackTempo = t)}
                  class="rounded-[10px] border px-2.5 py-1 font-mono transition {playbackTempo === t ? 'border-[#0a0a0a] bg-[#0a0a0a] text-white' : 'border-[#e5e5e5] bg-[#fafafa] text-[#444141]'}"
                >
                  {t}x
                </button>
              {/each}
            </div>
          </div>

          <!-- Waveform Mode -->
          <div>
            <span class="font-medium text-[#444141]">声波振幅模式</span>
            <div class="mt-2 flex items-center gap-1.5">
              <button
                type="button"
                onclick={() => (waveformMode = 'dynamic')}
                class="rounded-[10px] border px-2.5 py-1 transition {waveformMode === 'dynamic' ? 'border-[#0a0a0a] bg-[#0a0a0a] text-white' : 'border-[#e5e5e5] bg-[#fafafa] text-[#444141]'}"
              >
                动态律动
              </button>
              <button
                type="button"
                onclick={() => (waveformMode = 'mute')}
                class="rounded-[10px] border px-2.5 py-1 transition {waveformMode === 'mute' ? 'border-[#0a0a0a] bg-[#0a0a0a] text-white' : 'border-[#e5e5e5] bg-[#fafafa] text-[#444141]'}"
              >
                极简静音
              </button>
            </div>
          </div>

          <!-- System Status Toggle -->
          <div>
            <span class="font-medium text-[#444141]">系统健康指示状态</span>
            <div class="mt-2 flex items-center gap-1.5">
              <button
                type="button"
                onclick={() => (systemStatus = 'operational')}
                class="rounded-[10px] border px-2.5 py-1 transition {systemStatus === 'operational' ? 'border-[#22c55e] bg-[#22c55e]/10 text-[#22c55e]' : 'border-[#e5e5e5] bg-[#fafafa] text-[#444141]'}"
              >
                🟢 正常
              </button>
              <button
                type="button"
                onclick={() => (systemStatus = 'degraded')}
                class="rounded-[10px] border px-2.5 py-1 transition {systemStatus === 'degraded' ? 'border-[#eab308] bg-[#eab308]/10 text-[#ca8a04]' : 'border-[#e5e5e5] bg-[#fafafa] text-[#444141]'}"
              >
                🟡 降级
              </button>
              <button
                type="button"
                onclick={() => (systemStatus = 'maintenance')}
                class="rounded-[10px] border px-2.5 py-1 transition {systemStatus === 'maintenance' ? 'border-[#e7000b] bg-[#e7000b]/10 text-[#e7000b]' : 'border-[#e5e5e5] bg-[#fafafa] text-[#444141]'}"
              >
                🔴 维护
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  {:else if activeTab === 'code'}
    <CodeBlock code={snippetCode} language="html" title="MegaFooter.svelte" />
  {:else if activeTab === 'tokens'}
    <CodeBlock code={tokensSpec} language="css" title="Mega Footer Design Tokens" />
  {/if}
</div>
