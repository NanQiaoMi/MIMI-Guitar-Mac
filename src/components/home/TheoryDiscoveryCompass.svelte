<script lang="ts">
  const levels = [
    {
      level: 1,
      stage: '启蒙破冰',
      name: '零基础 · 启蒙',
      tag: 'L1',
      desc: '单音旋律、入门开放和弦与简单分解扫弦',
      badge: 'text-[#2e7d32] bg-[#2e7d32]/10 border-[#2e7d32]/25',
      color: '#2e7d32',
      reps: ['小星星', '老男孩'],
      url: '/tabs?difficulty=1',
    },
    {
      level: 2,
      stage: '弹唱基石',
      name: '初级 · 熟练弹唱',
      tag: 'L2',
      desc: '常用大调开放和弦、基础切音与前奏滑音',
      badge: 'text-[#00838f] bg-[#00838f]/10 border-[#00838f]/25',
      color: '#00838f',
      reps: ['晴天', '后来', '平凡之路'],
      url: '/tabs?difficulty=2',
    },
    {
      level: 3,
      stage: '复调独奏',
      name: '中级 · 进阶独奏',
      tag: 'L3',
      desc: 'F大横按攻克、击勾弦与中级指弹复调编曲',
      badge: 'text-[#1565c0] bg-[#1565c0]/10 border-[#1565c0]/25',
      color: '#1565c0',
      reps: ['反方向的钟', '我记得', '海阔天空'],
      url: '/tabs?difficulty=3',
    },
    {
      level: 4,
      stage: '舞台炫技',
      name: '高级 · 舞台指弹',
      tag: 'L4',
      desc: '拍弦（Slap）、点弦、人工泛音与复杂变拍子',
      badge: 'text-[#e65100] bg-[#e65100]/10 border-[#e65100]/25',
      color: '#e65100',
      reps: ['卡农', '加州旅馆', '风之诗'],
      url: '/tabs?difficulty=4',
    },
    {
      level: 5,
      stage: '大师造极',
      name: '专业 · 大师总谱',
      tag: 'L5',
      desc: '多声部交响化吉他、特殊调弦法与极速独奏',
      badge: 'text-[#8f6d2b] bg-[#8f6d2b]/10 border-[#8f6d2b]/25',
      color: '#8f6d2b',
      reps: ['Fight', 'Wings', '黄昏'],
      url: '/tabs?difficulty=5',
    },
  ];

  const keyFamilies = [
    { key: 'C', tonic: 'C', title: 'C 大调', mood: '纯净基石 · 温暖明朗', chords: 'C · Dm · Em · F · G · Am', color: '#1565c0' },
    { key: 'G', tonic: 'G', title: 'G 大调', mood: '民谣灵魂 · 清澈开阔', chords: 'G · Am · Bm · C · D · Em', color: '#2e7d32' },
    { key: 'D', tonic: 'D', title: 'D 大调', mood: '明快辉煌 · 抒情指弹', chords: 'D · Em · F#m · G · A · Bm', color: '#e65100' },
    { key: 'A', tonic: 'A', title: 'A 大调', mood: '清亮激昂 · 流行摇滚', chords: 'A · Bm · C#m · D · E · F#m', color: '#7b1fa2' },
    { key: 'E', tonic: 'E', title: 'E 大调', mood: '浑厚深沉 · 蓝调布鲁斯', chords: 'E · F#m · G#m · A · B · C#m', color: '#c2185b' },
    { key: 'F', tonic: 'F', title: 'F 大调', mood: '柔和浪漫 · 横按试炼', chords: 'F · Gm · Am · Bb · C · Dm', color: '#00838f' },
    { key: 'Em', tonic: 'Em', title: 'Em 小调', mood: '苍凉质朴 · 幽谷民谣', chords: 'Em · F#dim · G · Am · Bm · C', color: '#5c4a38' },
    { key: 'Am', tonic: 'Am', title: 'Am 小调', mood: '凄美深情 · 经典流行', chords: 'Am · Bdim · C · Dm · Em · F', color: '#c84b31' },
  ];

  const styleRows = [
    { value: 101, title: '流行', desc: '流行金曲 · 抒情弹唱', icon: '🎤' },
    { value: 102, title: '摇滚', desc: '经典摇滚 · 电声热血', icon: '⚡' },
    { value: 103, title: '民谣', desc: '原声吉他 · 校园诗意', icon: '🎸' },
    { value: 105, title: '配乐', desc: '影视原声 · 游戏动漫', icon: '🎬' },
    { value: 107, title: '乡村', desc: '指尖律动 · 欢快叙事', icon: '🌾' },
    { value: 109, title: '金属', desc: '强力和弦 · 极速失真', icon: '🔥' },
  ];
</script>

<section class="mt-16 sm:mt-20">
  <!-- Section Title Header -->
  <div class="flex items-end justify-between mb-6">
    <div>
      <div class="flex items-center gap-2">
        <span class="h-4 w-1.5 bg-gradient-to-b from-[#c49a45] to-[#8f6d2b] rounded-full shadow-2xs"></span>
        <h2 class="font-serif text-2xl sm:text-3xl font-bold tracking-tight text-[#2d2417]">
          乐理进阶天梯与调性探索罗盘
        </h2>
      </div>
      <p class="text-xs sm:text-sm text-[#8c7b68] font-serif mt-1 pl-4">
        清晰规划你的吉他研习路线，从零基础启蒙到专业大师级独奏
      </p>
    </div>
  </div>

  <!-- Progressive Connected Stage Breadcrumbs -->
  <div class="mb-5 flex flex-wrap items-center gap-2 rounded-2xl border border-[#e8e2d4] bg-[#faf7f2]/80 px-4 py-2.5 shadow-2xs">
    {#each levels as lvl, idx}
      <div class="flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-serif font-bold" style="color: {lvl.color}; background-color: {lvl.color}15;">
        <span class="h-1.5 w-1.5 rounded-full" style="background-color: {lvl.color};"></span>
        <span>{lvl.tag} {lvl.stage}</span>
      </div>
      {#if idx < levels.length - 1}
        <span class="text-xs text-[#d5cbb8]">→</span>
      {/if}
    {/each}
  </div>

  <!-- Part 1: L1~L5 Level Ladder (5 Steps Grid) -->
  <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-5 gap-3.5 sm:gap-4">
    {#each levels as lvl}
      <a
        href={lvl.url}
        class="group relative flex flex-col justify-between rounded-2xl border bg-[#ffffff] p-4 shadow-[0_4px_16px_rgba(76,59,43,0.04)] hover:shadow-[0_12px_28px_rgba(196,154,69,0.15)] transition-all duration-300 overflow-hidden"
        style="border-color: {lvl.color}35;"
      >
        <div>
          <!-- Level Tag -->
          <div class="flex items-center justify-between">
            <span class="rounded-full border px-2 py-0.5 font-mono text-[11px] font-bold {lvl.badge}">
              {lvl.tag} · {lvl.stage}
            </span>
            <span class="text-[10px] font-mono text-[#a89b8a]">LEVEL 0{lvl.level}</span>
          </div>

          <!-- Level Name -->
          <h3 class="font-serif text-base font-bold text-[#2d2926] mt-3 group-hover:text-[#966b26] transition-colors">
            {lvl.name}
          </h3>

          <!-- Description -->
          <p class="mt-2 text-xs font-serif text-[#705c42] leading-relaxed line-clamp-3">
            {lvl.desc}
          </p>
        </div>

        <!-- Representative Repertoire Pills -->
        <div class="mt-4 pt-3 border-t border-[#f0eae0]">
          <div class="text-[10px] font-serif text-[#8c7b68] mb-1.5">经典研习代表作:</div>
          <div class="flex flex-wrap gap-1">
            {#each lvl.reps as song}
              <span class="rounded bg-[#fbf9f4] border border-[#e8e2d4] px-1.5 py-0.5 font-serif text-[10px] text-[#5c4a38]">
                《{song}》
              </span>
            {/each}
          </div>
        </div>
      </a>
    {/each}
  </div>

  <!-- Part 2: Key Families & Style Genres Cloud -->
  <div class="mt-8 grid grid-cols-1 lg:grid-cols-12 gap-5 sm:gap-6">
    <!-- Left: Key Family Color Cards (7 Cols) -->
    <div class="lg:col-span-7 rounded-3xl border border-[#e2d8c3] bg-[#faf7f2] p-5 sm:p-6 shadow-xs flex flex-col justify-between">
      <div>
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-2">
            <h3 class="font-serif text-base sm:text-lg font-bold text-[#2d2926]">
              常用调性色彩与和弦家族
            </h3>
            <span class="rounded-full bg-[#c49a45]/15 px-2 py-0.5 font-serif text-[10px] font-bold text-[#966b26]">
              8大核心调性
            </span>
          </div>
          <span class="text-xs font-serif text-[#8c7b68] hidden sm:inline">点击快速探索对应调性曲谱</span>
        </div>

        <div class="grid grid-cols-2 sm:grid-cols-4 gap-2.5">
          {#each keyFamilies as item}
            <a
              href={`/tabs?key=${encodeURIComponent(item.key)}`}
              class="group rounded-2xl border border-[#e0d6c0] bg-[#ffffff] p-3 transition-all hover:border-[#c49a45] hover:shadow-sm"
            >
              <div class="flex items-center gap-1.5 mb-1">
                <span class="flex h-5 w-5 items-center justify-center rounded-full text-[11px] font-bold text-white shadow-2xs" style="background-color: {item.color};">
                  {item.tonic}
                </span>
                <span class="font-serif text-xs font-bold text-[#2d2926] group-hover:text-[#966b26]">
                  {item.title}
                </span>
              </div>
              <p class="text-[9.5px] font-serif text-[#8c7b68] truncate mb-1">
                {item.mood}
              </p>
              <span class="block text-[9px] font-mono font-medium truncate" style="color: {item.color};">
                {item.chords}
              </span>
            </a>
          {/each}
        </div>
      </div>
    </div>

    <!-- Right: Genre Tag Cloud & Studio Callout (5 Cols) -->
    <div class="lg:col-span-5 rounded-3xl border border-[#e2d8c3] bg-[#ffffff] p-5 sm:p-6 shadow-xs flex flex-col justify-between">
      <div>
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-2">
            <h3 class="font-serif text-base sm:text-lg font-bold text-[#2d2926]">
              曲风分类与编曲体裁
            </h3>
            <span class="rounded-full bg-[#8c7b68]/15 px-2 py-0.5 font-serif text-[10px] font-medium text-[#705c42]">
              6大体裁
            </span>
          </div>
          <a href="/tabs" class="text-xs font-serif text-[#966b26] hover:underline">全部曲谱 →</a>
        </div>

        <div class="grid grid-cols-2 sm:grid-cols-3 gap-2">
          {#each styleRows as style}
            <a
              href={`/tabs?style=${style.value}`}
              class="flex items-center gap-2 rounded-xl border border-[#e0d6c0] bg-[#fbf9f4] p-2 hover:border-[#c49a45] hover:bg-[#c49a45]/10 transition-all group"
            >
              <span class="text-sm">{style.icon}</span>
              <div class="min-w-0">
                <div class="font-serif text-xs font-bold text-[#2d2926] group-hover:text-[#966b26]">{style.title}</div>
                <div class="text-[9px] font-serif text-[#8c7b68] truncate">{style.desc}</div>
              </div>
            </a>
          {/each}
        </div>
      </div>

      <div class="mt-4 rounded-2xl border border-[#c49a45]/30 bg-[#c49a45]/10 p-3 flex items-center justify-between gap-2 text-xs font-serif">
        <div class="min-w-0">
          <span class="font-bold text-[#8f6d2b] block">未找到想要的曲谱？</span>
          <span class="text-[10px] text-[#8c7b68] truncate block">支持导入 GP/IBE/XHE，或进入制谱工坊编排</span>
        </div>
        <div class="flex items-center gap-1.5 shrink-0">
          <a
            href="/upload"
            class="rounded-full bg-[#2d2926] px-2.5 py-1 text-[11px] font-medium text-[#faf8f5] hover:bg-[#966b26] transition-colors"
          >
            上传自制谱
          </a>
          <a
            href="/studio"
            class="rounded-full border border-[#c49a45] bg-white px-2.5 py-1 text-[11px] font-medium text-[#966b26] hover:bg-[#fbf9f4] transition-colors"
          >
            制谱工坊
          </a>
        </div>
      </div>
    </div>
  </div>
</section>
