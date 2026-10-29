<script lang="ts">
  import CodeBlock from './CodeBlock.svelte';

  // Categories
  const categories = [
    { id: 'all', label: '全部曲谱', count: 1284 },
    { id: 'pop', label: '流行金曲', count: 482 },
    { id: 'rock', label: '摇滚殿堂', count: 215 },
    { id: 'folk', label: '民谣弹唱', count: 198 },
    { id: 'fingerstyle', label: '原声指弹', count: 246 },
    { id: 'acg', label: '动漫二次元', count: 88 },
    { id: 'classic', label: '古典/跨界', count: 55 },
  ];

  // Forms
  const sheetForms = [
    { id: 'all', label: '全部形式' },
    { id: '1', label: '🎸 弹唱谱' },
    { id: '2', label: '🎼 指弹谱' },
    { id: '3', label: '🎹 和弦谱' },
    { id: '4', label: '📑 六线谱' },
  ];

  // Difficulties
  const difficulties = [
    { level: 1, name: '零基础', desc: '开放和弦 (C/G/Am/Em)，简单 4/4 拍扫弦或下扫分解，适合第 1 周新手', chords: '3~4 个基础和弦' },
    { level: 2, name: '初级', desc: '加入小横按或简单切音，包含基础低音交替与三指法分解', chords: '4~6 个常见和弦' },
    { level: 3, name: '中级', desc: '包含标准大横按 F/Bm、拍弦技巧与 16 分音符切分节奏', chords: '6~8 个和弦/包含大横按' },
    { level: 4, name: '高级', desc: '多把位移动、快速扫弦点弦、特殊调弦法 (DADGAD) 与复调声部', chords: '9+ 个和弦/复音指弹' },
    { level: 5, name: '专业大师', desc: '押尾/Tommy 级大师独奏、极速轮指、敲击箱体与高把位速弹', chords: '全指板复合技巧' },
  ];

  // Matrix Sample Data
  const guitarMatrix: Record<string, number> = {
    '1:1': 142, '1:2': 18, '1:3': 64, '1:4': 89,
    '2:1': 210, '2:2': 45, '2:3': 88, '2:4': 132,
    '3:1': 184, '3:2': 92, '3:3': 51, '3:4': 160,
    '4:1': 65, '4:2': 78, '4:3': 12, '4:4': 95,
    '5:1': 18, '5:2': 46, '5:3': 4, '5:4': 38,
  };

  const ukuleleMatrix: Record<string, number> = {
    '1:1': 95, '1:2': 12, '1:3': 42, '1:4': 35,
    '2:1': 118, '2:2': 28, '2:3': 56, '2:4': 48,
    '3:1': 74, '3:2': 36, '3:3': 22, '3:4': 41,
    '4:1': 22, '4:2': 19, '4:3': 8, '4:4': 15,
    '5:1': 6, '5:2': 11, '5:3': 2, '5:4': 8,
  };

  // State
  let selectedCategory = $state('all');
  let selectedForm = $state('all');
  let selectedDifficulty = $state(3);
  let hoveredDifficulty = $state<number | null>(null);
  let matrixInstrument = $state<'guitar' | 'ukulele'>('guitar');
  let activeTab = $state<'preview' | 'code' | 'tokens'>('preview');

  const curMatrix = $derived(matrixInstrument === 'guitar' ? guitarMatrix : ukuleleMatrix);

  // Spring capsule indicator position
  let categoryContainerRef = $state<HTMLElement | null>(null);
  let capsuleStyle = $state({ left: 0, width: 0, opacity: 0 });

  function updateCapsule(targetId: string) {
    if (!categoryContainerRef) return;
    const targetEl = categoryContainerRef.querySelector(`[data-cat-id="${targetId}"]`) as HTMLElement | null;
    if (targetEl) {
      const containerRect = categoryContainerRef.getBoundingClientRect();
      const targetRect = targetEl.getBoundingClientRect();
      capsuleStyle = {
        left: targetRect.left - containerRect.left,
        width: targetRect.width,
        opacity: 1,
      };
    }
  }

  function handleSelectCategory(id: string) {
    selectedCategory = id;
    updateCapsule(id);
  }

  $effect(() => {
    updateCapsule(selectedCategory);
  });

  const activeDiffInfo = $derived(
    difficulties.find((d) => d.level === (hoveredDifficulty ?? selectedDifficulty)) || difficulties[2]
  );

  const snippetCode = `<!-- Spring 胶囊 FLIP 切换与 5 段渐进难度条 -->
<div class="relative flex items-center gap-1 rounded-[18px] border border-[#e5e5e5] bg-[#f5f5f5] p-1">
  <!-- FLIP 弹簧滑动背景胶囊 -->
  <div 
    class="absolute top-1 bottom-1 rounded-[14px] bg-[#0a0a0a] transition-all duration-300 ease-[cubic-bezier(0.16,1,0.3,1)] pointer-events-none"
    style="left: \${capsule.left}px; width: \${capsule.width}px;"
  />
  {#each categories as cat}
    <button 
      class="relative z-10 px-3.5 py-1.5 text-xs font-medium transition-colors \${selected === cat.id ? 'text-white' : 'text-[#444141] hover:text-[#0a0a0a]'}"
      onclick={() => selectCategory(cat.id)}
    >
      {cat.label}
    </button>
  {/each}
</div>

<!-- 5 段逐格难度脉冲指示器 -->
<div class="flex items-center gap-1">
  {#each Array(5) as _, i}
    <div 
      class="h-2.5 w-7 rounded-full transition-all duration-300 ease-out"
      style="
        background-color: \${i < currentLevel ? (currentLevel >= 4 ? '#e7000b' : '#41a1cf') : '#dee2de'};
        transform: scale(\${i + 1 === currentLevel ? 1.08 : 1});
        box-shadow: \${i < currentLevel ? '0 0 6px rgba(65,161,207,0.3)' : 'none'};
      "
    />
  {/each}
</div>`;

  const tokensSpec = `/* Refero UI FilterBar & Difficulty Tokens */
--radius-filter-pill: 18px;
--radius-filter-item: 14px;
--difficulty-bar-h: 8px;
--difficulty-bar-w: 24px;
--color-diff-easy: #41a1cf;
--color-diff-hard: #e7000b;
--color-diff-empty: #dee2de;
--spring-pill: cubic-bezier(0.16, 1, 0.3, 1);`;
</script>

<div class="space-y-8">
  <!-- Sub-Header & Switcher -->
  <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between border-b border-[#e5e5e5] pb-5">
    <div>
      <div class="inline-flex items-center gap-2 rounded-[18px] border border-[#e5e5e5] bg-[#fafafa] px-3 py-1 text-xs font-medium text-[#737373]">
        <span class="h-2 w-2 rounded-full bg-[#41a1cf]"></span>
        MODULE 04 · 弹簧胶囊与难度律动
      </div>
      <h2 class="mt-2 font-display text-2xl text-[#0a0a0a]">FilterBar & 难度指示矩阵 (Spring Capsule & 5-Step Pulse)</h2>
      <p class="mt-1 text-sm text-[#737373]">
        物理弹簧 FLIP 胶囊背景滑动、5 段逐格难度脉冲亮起、Tooltip 即时释义与乐器难度交叉统计表。
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
    <div class="grid grid-cols-1 gap-6 lg:grid-cols-12">
      <!-- Main Left Interactive Panel -->
      <div class="lg:col-span-8 space-y-6">
        <!-- 1. SPRING CAPSULE CATEGORY BAR -->
        <div class="rounded-[24px] border border-[#e5e5e5] bg-white p-6 shadow-xs space-y-4">
          <div class="flex items-center justify-between">
            <h3 class="font-display text-base text-[#0a0a0a]">1. 弹簧胶囊分类切换器 (Spring FLIP Capsule)</h3>
            <span class="text-xs font-mono text-[#737373]">Active: {selectedCategory}</span>
          </div>

          <div
            bind:this={categoryContainerRef}
            class="relative flex flex-wrap items-center gap-1 rounded-[20px] border border-[#e5e5e5] bg-[#f5f5f5]/80 p-1.5"
          >
            <!-- Sliding Capsule Background -->
            <div
              class="absolute top-1.5 bottom-1.5 rounded-[14px] bg-[#0a0a0a] transition-all duration-300 ease-[cubic-bezier(0.16,1,0.3,1)] pointer-events-none shadow-xs"
              style="
                left: {capsuleStyle.left}px;
                width: {capsuleStyle.width}px;
                opacity: {capsuleStyle.opacity};
              "
            ></div>

            {#each categories as cat}
              <button
                type="button"
                data-cat-id={cat.id}
                onclick={() => handleSelectCategory(cat.id)}
                class="relative z-10 rounded-[14px] px-3.5 py-1.5 text-xs font-medium transition-colors duration-200 select-none {selectedCategory === cat.id ? 'text-white' : 'text-[#444141] hover:text-[#0a0a0a]'}"
              >
                <span>{cat.label}</span>
                <span class="ml-1 text-[10px] opacity-70">({cat.count})</span>
              </button>
            {/each}
          </div>

          <!-- Secondary Filters (Pill Chips) -->
          <div class="flex flex-wrap items-center gap-2 pt-2 border-t border-[#e5e5e5]">
            <span class="text-xs font-medium text-[#737373]">曲谱形式:</span>
            {#each sheetForms as form}
              <button
                type="button"
                onclick={() => (selectedForm = form.id)}
                class="chip {selectedForm === form.id ? 'chip-active' : ''}"
              >
                {form.label}
              </button>
            {/each}
          </div>
        </div>

        <!-- 2. 5-BAR PROGRESSIVE DIFFICULTY SELECTOR -->
        <div class="rounded-[24px] border border-[#e5e5e5] bg-white p-6 shadow-xs space-y-5">
          <div class="flex items-center justify-between">
            <div>
              <h3 class="font-display text-base text-[#0a0a0a]">2. 5 段渐进难度指示条 (5-Step Pulse Matrix)</h3>
              <p class="text-xs text-[#737373] mt-0.5">点击或悬停不同难度等级，体验逐格点亮与阻尼脉冲动效。</p>
            </div>
            <span class="rounded-[12px] bg-[#fafafa] border border-[#e5e5e5] px-2.5 py-1 text-xs font-mono text-[#0a0a0a]">
              Level {selectedDifficulty} / 5
            </span>
          </div>

          <!-- Interactive 5-Step Bar Control -->
          <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 rounded-[20px] border border-[#e5e5e5] bg-[#fafafa] p-4">
            <div class="flex items-center gap-2">
              {#each difficulties as d}
                <button
                  type="button"
                  onmouseenter={() => (hoveredDifficulty = d.level)}
                  onmouseleave={() => (hoveredDifficulty = null)}
                  onclick={() => (selectedDifficulty = d.level)}
                  class="group flex flex-col items-center gap-1.5 focus:outline-none"
                  title={d.name}
                >
                  <div
                    class="h-3 w-8 sm:w-10 rounded-full transition-all duration-300 ease-out cursor-pointer"
                    style="
                      background-color: {d.level <= (hoveredDifficulty ?? selectedDifficulty)
                        ? ((hoveredDifficulty ?? selectedDifficulty) >= 4 ? '#e7000b' : '#41a1cf')
                        : '#dee2de'};
                      transform: {d.level === (hoveredDifficulty ?? selectedDifficulty) ? 'scaleY(1.3) scaleX(1.05)' : 'scale(1)'};
                      box-shadow: {d.level <= (hoveredDifficulty ?? selectedDifficulty) ? '0 0 8px rgba(65,161,207,0.35)' : 'none'};
                    "
                  ></div>
                  <span class="text-[11px] font-medium transition-colors {d.level === (hoveredDifficulty ?? selectedDifficulty) ? 'text-[#0a0a0a] font-bold' : 'text-[#737373]'}">
                    L{d.level}
                  </span>
                </button>
              {/each}
            </div>

            <!-- Active Level Badge -->
            <div class="inline-flex items-center gap-2 rounded-[18px] bg-white border border-[#e5e5e5] px-3 py-1.5 shadow-xs">
              <span
                class="h-2.5 w-2.5 rounded-full animate-pulse"
                style="background-color: {(hoveredDifficulty ?? selectedDifficulty) >= 4 ? '#e7000b' : '#41a1cf'};"
              ></span>
              <span class="text-xs font-semibold text-[#0a0a0a]">
                {activeDiffInfo.name} (Level {activeDiffInfo.level})
              </span>
            </div>
          </div>

          <!-- Difficulty Tooltip Detail Card -->
          <div class="rounded-[18px] border border-[#e5e5e5] bg-white p-4 shadow-xs">
            <div class="flex items-start justify-between gap-3">
              <div>
                <span class="text-xs font-medium text-[#737373]">难度特征与练习要求:</span>
                <p class="text-xs text-[#0a0a0a] mt-1 font-medium leading-relaxed">
                  {activeDiffInfo.desc}
                </p>
              </div>
              <div class="shrink-0 rounded-[12px] bg-[#f5f5f5] px-2.5 py-1 text-[11px] text-[#444141] font-mono">
                {activeDiffInfo.chords}
              </div>
            </div>
          </div>
        </div>

        <!-- 3. DIFFICULTY MATRIX TABLE -->
        <div class="rounded-[24px] border border-[#e5e5e5] bg-white p-6 shadow-xs space-y-4">
          <div class="flex items-center justify-between">
            <div>
              <h3 class="font-display text-base text-[#0a0a0a]">3. 乐器难度矩阵交叉表 (Difficulty Matrix Table)</h3>
              <p class="text-xs text-[#737373]">点击单元格可测试联动筛选响应。</p>
            </div>

            <!-- Instrument Switch -->
            <div class="flex items-center rounded-[14px] border border-[#e5e5e5] bg-[#f5f5f5] p-0.5 text-xs font-medium">
              <button
                type="button"
                onclick={() => (matrixInstrument = 'guitar')}
                class="rounded-[10px] px-3 py-1 transition {matrixInstrument === 'guitar' ? 'bg-[#0a0a0a] text-white' : 'text-[#737373]'}"
              >
                🎸 吉他矩阵
              </button>
              <button
                type="button"
                onclick={() => (matrixInstrument = 'ukulele')}
                class="rounded-[10px] px-3 py-1 transition {matrixInstrument === 'ukulele' ? 'bg-[#0a0a0a] text-white' : 'text-[#737373]'}"
              >
                🌴 尤克里里
              </button>
            </div>
          </div>

          <!-- Table Container -->
          <div class="overflow-x-auto rounded-[18px] border border-[#e5e5e5]">
            <table class="w-full text-xs text-left border-collapse">
              <thead>
                <tr class="bg-[#fafafa] border-b border-[#e5e5e5] text-[#737373]">
                  <th class="p-3 font-medium">难度等级</th>
                  <th class="p-3 font-medium text-center">弹唱谱</th>
                  <th class="p-3 font-medium text-center">指弹谱</th>
                  <th class="p-3 font-medium text-center">和弦谱</th>
                  <th class="p-3 font-medium text-center">六线谱</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-[#e5e5e5]">
                {#each difficulties as d}
                  <tr class="hover:bg-[#fafafa]/80 transition {selectedDifficulty === d.level ? 'bg-[#41a1cf]/5' : ''}">
                    <td class="p-3 font-medium text-[#0a0a0a] flex items-center gap-2">
                      <span class="h-2 w-2 rounded-full" style="background-color: {d.level >= 4 ? '#e7000b' : '#41a1cf'};"></span>
                      <span>Level {d.level} · {d.name}</span>
                    </td>
                    {#each [1, 2, 3, 4] as formId}
                      {@const count = curMatrix[`${d.level}:${formId}`] || 0}
                      <td class="p-3 text-center">
                        <button
                          type="button"
                          onclick={() => {
                            selectedDifficulty = d.level;
                            selectedForm = String(formId);
                          }}
                          class="inline-block rounded-[10px] border border-transparent px-2.5 py-1 font-mono transition hover:border-[#e5e5e5] hover:bg-white active:scale-95"
                        >
                          <span class="font-bold text-[#0a0a0a]">{count}</span>
                          <span class="text-[10px] text-[#737373]"> 首</span>
                        </button>
                      </td>
                    {/each}
                  </tr>
                {/each}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <!-- Right: Summary & Reset Controls -->
      <div class="lg:col-span-4 space-y-5">
        <div class="rounded-[24px] border border-[#e5e5e5] bg-white p-5 shadow-xs">
          <h3 class="font-display text-base text-[#0a0a0a]">🎛️ 筛选状态监控</h3>
          <p class="mt-1 text-xs text-[#737373]">当前多维过滤条件与联动统计。</p>

          <div class="mt-5 space-y-3 text-xs">
            <div class="flex justify-between border-b border-[#e5e5e5] pb-2">
              <span class="text-[#737373]">已选分类:</span>
              <span class="font-medium text-[#0a0a0a]">{categories.find((c) => c.id === selectedCategory)?.label}</span>
            </div>
            <div class="flex justify-between border-b border-[#e5e5e5] pb-2">
              <span class="text-[#737373]">已选形式:</span>
              <span class="font-medium text-[#0a0a0a]">{sheetForms.find((f) => f.id === selectedForm)?.label}</span>
            </div>
            <div class="flex justify-between border-b border-[#e5e5e5] pb-2">
              <span class="text-[#737373]">已选难度:</span>
              <span class="font-medium text-[#0a0a0a]">Level {selectedDifficulty} · {activeDiffInfo.name}</span>
            </div>
            <div class="flex justify-between border-b border-[#e5e5e5] pb-2">
              <span class="text-[#737373]">乐器矩阵:</span>
              <span class="font-medium text-[#0a0a0a]">{matrixInstrument === 'guitar' ? '吉他 (Guitar)' : '尤克里里 (Ukulele)'}</span>
            </div>

            <div class="pt-3 space-y-2">
              <button
                type="button"
                onclick={() => {
                  handleSelectCategory('all');
                  selectedForm = 'all';
                  selectedDifficulty = 1;
                }}
                class="w-full rounded-[18px] border border-[#e5e5e5] bg-[#fafafa] py-2 text-xs font-medium text-[#0a0a0a] hover:bg-[#f5f5f5] active:scale-95"
              >
                🔄 重置所有筛选条件
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  {:else if activeTab === 'code'}
    <CodeBlock code={snippetCode} language="html" title="FilterBar & DifficultyMatrix.svelte" />
  {:else if activeTab === 'tokens'}
    <CodeBlock code={tokensSpec} language="css" title="Filter & Matrix CSS Tokens" />
  {/if}
</div>
