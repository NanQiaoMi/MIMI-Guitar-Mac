<script lang="ts">
  import { getMotionMode } from '../../lib/ui/motion';
  function scrollToTop() {
    if (typeof window !== 'undefined') {
      window.scrollTo({ top: 0, behavior: getMotionMode() === 'full' ? 'smooth' : 'auto' });
    }
  }
</script>

<footer class="mt-20 border-t border-[#e2d8c3] bg-[#faf7f2] pt-14 pb-12 font-serif text-xs text-[#705c42]">
  <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-8 lg:gap-10 pb-12 border-b border-[#e8e2d4]">
      <!-- Brand Col (2 cols on lg) -->
      <div class="lg:col-span-2 space-y-4">
        <div class="flex items-center gap-3">
          <div class="flex h-9 w-9 items-center justify-center rounded-xl bg-[#2d2926] text-[#faf8f5] font-display font-bold text-base shadow-xs">
            M
          </div>
          <span class="font-display text-xl font-bold tracking-tight text-[#2d2926]">
            MIMI Guitar 乐谱与练习
          </span>
        </div>

        <p class="text-xs text-[#8c7b68] leading-relaxed max-w-sm">
          把每一份乐谱，都当作一页书来对待。为吉他与尤克里里演奏者提供乐谱浏览、播放控制和本地练习记录。
        </p>

        <div class="flex items-center gap-2 pt-2">
          <span class="flex h-5 w-5 items-center justify-center rounded-md border border-[#c84b31]/40 bg-[#c84b31]/10 text-[#c84b31] text-[10px] font-bold">
            印
          </span>
          <span class="text-[11px] text-[#a89b8a]">曲谱浏览 · 本地练习 · 个人备份</span>
        </div>
      </div>

      <!-- Col 1: 曲谱生态 -->
      <div class="space-y-3">
        <h4 class="font-display text-sm font-bold text-[#2d2926]">曲谱生态</h4>
        <ul class="space-y-2 text-[#705c42]">
          <li><a href="/tabs" class="hover:text-[#966b26] transition-colors">吉他谱大全</a></li>
          <li><a href="/ukulele" class="hover:text-[#966b26] transition-colors">尤克里里精选</a></li>
          <li><a href="/tabs?sheetForm=2" class="hover:text-[#966b26] transition-colors">指弹独奏谱</a></li>
          <li><a href="/tabs?sheetForm=1" class="hover:text-[#966b26] transition-colors">经典弹唱谱</a></li>
          <li><a href="/tabs?sort=1" class="hover:text-[#966b26] transition-colors">曲谱排序浏览</a></li>
        </ul>
      </div>

      <!-- Col 2: 核心功能 -->
      <div class="space-y-3">
        <h4 class="font-display text-sm font-bold text-[#2d2926]">核心功能</h4>
        <ul class="space-y-2 text-[#705c42]">
          <li><span class="text-[#8c7b68]">乐谱播放控制</span></li>
          <li><span class="text-[#8c7b68]">六线谱与简谱显示</span></li>
          <li><span class="text-[#8c7b68]">音轨播放设置</span></li>
          <li><span class="text-[#8c7b68]">吉他指板显示</span></li>
          <li><span class="text-[#8c7b68]">变调与移调设置</span></li>
        </ul>
      </div>

      <!-- Col 3: 乐理与工坊 -->
      <div class="space-y-3">
        <h4 class="font-display text-sm font-bold text-[#2d2926]">乐理与工坊</h4>
        <ul class="space-y-2 text-[#705c42]">
          <li><a href="/library" class="hover:text-[#966b26] transition-colors">个人导入曲谱</a></li>
          <li><a href="/motion" class="hover:text-[#966b26] transition-colors">动效与交互偏好</a></li>
          <li><a href="/tabs?key=G" class="hover:text-[#966b26] transition-colors">G 调和弦家族</a></li>
          <li><a href="/tabs?key=C" class="hover:text-[#966b26] transition-colors">C 调入门精选</a></li>
          <li><a href="/tabs?difficulty=1" class="hover:text-[#966b26] transition-colors">零基础新手天梯</a></li>
        </ul>
      </div>
    </div>

    <!-- Bottom Copyright & Back to Top -->
    <div class="mt-8 flex flex-col sm:flex-row items-center justify-between gap-4 text-[11px] text-[#a89b8a]">
      <p>© 2026 MIMI Guitar Workshop. All rights reserved.</p>

      <button
        type="button"
        onclick={scrollToTop}
        class="inline-flex min-h-[44px] items-center gap-1.5 rounded-full border border-[#e0d6c0] bg-[#ffffff] px-3.5 py-1 text-[#5c4a38] shadow-2xs hover:border-[#c49a45] hover:text-[#966b26] transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a]"
      >
        <span>↑ 返回顶部</span>
      </button>
    </div>
  </div>
</footer>
