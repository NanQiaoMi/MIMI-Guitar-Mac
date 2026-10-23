<script lang="ts">
  import { STYLE_OPTIONS } from '../../lib/tabQuery';

  const levels = [
    {
      level: 1,
      name: '零基础 · 启蒙',
      tag: 'L1',
      desc: '单音旋律、入门和弦与简单分解扫弦',
      badge: 'text-[#2e7d32] bg-[#2e7d32]/10 border-[#2e7d32]/25',
      representative: '《小星星》《老男孩》',
      url: '/tabs?difficulty=1',
    },
    {
      level: 2,
      name: '初级 · 熟练弹唱',
      tag: 'L2',
      desc: '常用大调开放和弦、基础切音与前奏滑音',
      badge: 'text-[#00838f] bg-[#00838f]/10 border-[#00838f]/25',
      representative: '《晴天》《后来》《平凡之路》',
      url: '/tabs?difficulty=2',
    },
    {
      level: 3,
      name: '中级 · 进阶独奏',
      tag: 'L3',
      desc: 'F大横按攻克、击勾弦与中级指弹复调编曲',
      badge: 'text-[#1565c0] bg-[#1565c0]/10 border-[#1565c0]/25',
      representative: '《反方向的钟》《我记得》《海阔天空》',
      url: '/tabs?difficulty=3',
    },
    {
      level: 4,
      name: '高级 · 舞台指弹',
      tag: 'L4',
      desc: '拍弦（Slap）、点弦、人工泛音与复杂变拍子',
      badge: 'text-[#e65100] bg-[#e65100]/10 border-[#e65100]/25',
      representative: '《卡农》《加州旅馆》《风之诗》',
      url: '/tabs?difficulty=4',
    },
    {
      level: 5,
      name: '专业 · 大师总谱',
      tag: 'L5',
      desc: '多声部交响化吉他、特殊调弦法与极速独奏',
      badge: 'text-[#b71c1c] bg-[#b71c1c]/10 border-[#b71c1c]/25',
      representative: '《Fight》《Wings You are the HERO》',
      url: '/tabs?difficulty=5',
    },
  ];

  const keyFamilies = [
    { key: 'C', title: 'C 大调', chords: 'C - Dm - Em - F - G - Am', color: '#1565c0' },
    { key: 'G', title: 'G 大调', chords: 'G - Am - Bm - C - D - Em', color: '#2e7d32' },
    { key: 'D', title: 'D 大调', chords: 'D - Em - F#m - G - A - Bm', color: '#e65100' },
    { key: 'A', title: 'A 大调', chords: 'A - Bm - C#m - D - E - F#m', color: '#7b1fa2' },
    { key: 'E', title: 'E 大调', chords: 'E - F#m - G#m - A - B - C#m', color: '#c2185b' },
    { key: 'F', title: 'F 大调', chords: 'F - Gm - Am - Bb - C - Dm', color: '#00838f' },
    { key: 'Em', title: 'Em 小调', chords: 'Em - F#dim - G - Am - Bm - C', color: '#5c4a38' },
    { key: 'Am', title: 'Am 小调', chords: 'Am - Bdim - C - Dm - Em - F', color: '#c84b31' },
  ];
</script>

<section class="mt-16">
  <!-- Section Title Header -->
  <div class="flex items-end justify-between mb-8">
    <div>
      <div class="flex items-center gap-2">
        <span class="h-4 w-1 bg-[#c49a45] rounded-full"></span>
        <h2 class="font-display text-2xl sm:text-3xl font-bold text-[#2d2926]">
          乐理进阶天梯与调性探索罗盘
        </h2>
      </div>
      <p class="text-xs sm:text-sm text-[#8c7b68] font-serif mt-1 pl-6">
        清晰规划你的吉他研习路线，从零基础启蒙到专业大师级独奏
      </p>
    </div>
  </div>

  <!-- Part 1: L1~L5 Level Ladder (5 Steps Grid) -->
  <div class="grid grid-cols-1 md:grid-cols-5 gap-4">
    {#each levels as lvl}
      <a
        href={lvl.url}
        class="group relative flex flex-col justify-between rounded-2xl border border-[#e2d8c3] bg-[#ffffff] p-4.5 shadow-[0_4px_16px_rgba(76,59,43,0.04)] hover:border-[#c49a45] hover:shadow-[0_12px_28px_rgba(196,154,69,0.15)] transition-all duration-300 overflow-hidden"
      >
        <div>
          <!-- Level Tag -->
          <div class="flex items-center justify-between">
            <span class="rounded-full border px-2 py-0.5 font-mono text-[11px] font-bold {lvl.badge}">
              {lvl.tag}
            </span>
            <span class="text-[10px] font-mono text-[#a89b8a]">LEVEL 0{lvl.level}</span>
          </div>

          <!-- Level Name -->
          <h3 class="font-display text-base font-bold text-[#2d2926] mt-3 group-hover:text-[#966b26] transition-colors">
            {lvl.name}
          </h3>

          <!-- Description -->
          <p class="mt-2 text-xs font-serif text-[#705c42] leading-relaxed line-clamp-3">
            {lvl.desc}
          </p>
        </div>

        <!-- Representative Tab -->
        <div class="mt-4 pt-3 border-t border-[#f0eae0]">
          <div class="text-[10px] font-serif text-[#8c7b68]">经典研习代表作:</div>
          <div class="text-xs font-serif font-medium text-[#2d2926] mt-0.5 truncate">
            {lvl.representative}
          </div>
        </div>
      </a>
    {/each}
  </div>

  <!-- Part 2: Key Families & Style Genres Cloud -->
  <div class="mt-10 grid grid-cols-1 lg:grid-cols-12 gap-6">
    <!-- Left: Key Family Color Cards (7 Cols) -->
    <div class="lg:col-span-7 rounded-3xl border border-[#e2d8c3] bg-[#faf7f2] p-6 shadow-xs">
      <div class="flex items-center justify-between mb-4">
        <h3 class="font-display text-lg font-bold text-[#2d2926]">
          常用调性色彩与和弦家族
        </h3>
        <span class="text-xs font-serif text-[#8c7b68]">点击快速探索对应调性曲谱</span>
      </div>

      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
        {#each keyFamilies as item}
          <a
            href={`/tabs?key=${encodeURIComponent(item.key)}`}
            class="group rounded-2xl border border-[#e0d6c0] bg-[#ffffff] p-3 text-center transition-all hover:border-[#c49a45] hover:shadow-sm"
          >
            <span class="block font-mono text-lg font-bold text-[#2d2926] group-hover:text-[#966b26]">
              {item.title}
            </span>
            <span class="block text-[10px] font-mono text-[#8c7b68] mt-1 truncate">
              {item.chords}
            </span>
          </a>
        {/each}
      </div>
    </div>

    <!-- Right: Genre Tag Cloud (5 Cols) -->
    <div class="lg:col-span-5 rounded-3xl border border-[#e2d8c3] bg-[#ffffff] p-6 shadow-xs flex flex-col justify-between">
      <div>
        <div class="flex items-center justify-between mb-4">
          <h3 class="font-display text-lg font-bold text-[#2d2926]">
            曲风分类与编曲体裁
          </h3>
          <a href="/tabs" class="text-xs font-serif text-[#966b26] hover:underline">全部 →</a>
        </div>

        <div class="flex flex-wrap gap-2.5">
          {#each STYLE_OPTIONS.filter((s) => s.value > 0) as style}
            <a
              href={`/tabs?style=${style.value}`}
              class="rounded-full border border-[#e0d6c0] bg-[#fbf9f4] px-3.5 py-1.5 text-xs font-serif text-[#5c4a38] hover:border-[#c49a45] hover:bg-[#c49a45]/15 hover:text-[#966b26] transition-all"
            >
              {style.label}
            </a>
          {/each}
        </div>
      </div>

      <div class="mt-6 rounded-2xl border border-[#c49a45]/30 bg-[#c49a45]/10 p-3.5 flex items-center justify-between text-xs font-serif">
        <span class="text-[#8f6d2b]">未找到想要的曲谱？</span>
        <a
          href="/upload"
          class="rounded-full bg-[#2d2926] px-3 py-1 font-medium text-[#faf8f5] hover:bg-[#966b26] transition-colors"
        >
          上传自制手稿 →
        </a>
      </div>
    </div>
  </div>
</section>
