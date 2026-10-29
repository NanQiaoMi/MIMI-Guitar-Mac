<script lang="ts">
  export interface CtaProps {
    totalTabs?: number;
  }

  let { totalTabs = 12121 }: CtaProps = $props();
</script>

<section class="mt-20">
  <div
    class="relative overflow-hidden rounded-3xl border border-[#c49a45]/50 bg-gradient-to-br from-[#2d2926] via-[#3a342f] to-[#25211e] p-8 sm:p-12 text-center text-[#faf8f5] shadow-[0_20px_50px_rgba(45,41,38,0.3)]"
  >
    <!-- Background Amber Glow & Sound Waves Art -->
    <div class="pointer-events-none absolute -left-20 -bottom-20 h-72 w-72 rounded-full bg-[#c49a45]/20 blur-3xl"></div>
    <div class="pointer-events-none absolute -right-20 -top-20 h-72 w-72 rounded-full bg-[#c84b31]/15 blur-3xl"></div>
    <div class="pointer-events-none absolute inset-0 opacity-10 bg-[radial-gradient(#ffffff_1px,transparent_1px)] [background-size:20px_20px]"></div>

    <div class="relative z-10 max-w-2xl mx-auto space-y-6">
      <div class="inline-flex items-center gap-2 rounded-full border border-[#c49a45]/50 bg-[#ffffff]/10 px-4 py-1 text-xs font-serif backdrop-blur-md">
        <span class="text-[#c49a45]">✦</span>
        <span class="font-mono text-[#e2c078]">OVER {totalTabs.toLocaleString()} MASTERPIECES</span>
        <span class="text-[#c49a45]">✦</span>
      </div>

      <h2 class="font-display text-3xl sm:text-4xl lg:text-5xl font-bold tracking-tight text-[#ffffff] leading-tight">
        立即开启你的数字乐谱研习之旅
      </h2>

      <p class="text-sm sm:text-base text-[#d5c7b0] font-serif leading-relaxed">
        告别劣质 PDF 与错漏百出的手抄谱。在 60FPS 高清原声伴奏中，重拾指尖拨动琴弦的纯粹感动。
      </p>

      <div class="pt-2 flex flex-col sm:flex-row items-center justify-center gap-4">
        <a
          href="/tabs"
          class="w-full sm:w-auto inline-flex items-center justify-center gap-2 rounded-2xl bg-gradient-to-r from-[#c49a45] to-[#dfb55a] px-8 py-3.5 text-sm font-serif font-bold text-[#2d2926] shadow-lg hover:brightness-110 active:scale-95 transition-all"
        >
          <span>立即探索曲谱库</span>
          <span>→</span>
        </a>

        <a
          href="/upload"
          class="w-full sm:w-auto inline-flex items-center justify-center gap-2 rounded-2xl border border-[#d5c7b0]/30 bg-[#ffffff]/10 px-8 py-3.5 text-sm font-serif font-medium text-[#faf8f5] backdrop-blur-sm hover:bg-[#ffffff]/20 active:scale-95 transition-all"
        >
          <span>上传我的乐谱</span>
        </a>
      </div>
    </div>
  </div>
</section>
