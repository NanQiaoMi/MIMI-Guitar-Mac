<script lang="ts">
  import MotionDialog from '../ui/MotionDialog.svelte';

  let {
    isOpen = false,
    fallbackFocusSelector,
    onClose,
  }: {
    isOpen: boolean;
    fallbackFocusSelector?: string;
    onClose?: () => void;
  } = $props();

  const sections = [
    {
      title: '快速上手',
      icon: '🎼',
      items: [
        ['选位置', '点乐谱画布定位小节和拍位；画布拥有键盘焦点时，方向键可逐拍、逐弦移动。'],
        ['录音符', '画布拥有键盘焦点时输入品位数字，0 表示空弦；输入 1 或 2 后稍等，或继续输入第二位组成 10–24 品。指板点击也可录入。'],
        ['录节奏', '先选时值，再输入音符。工具栏可切换附点、三连音、休止符；拍数不足或溢出时按提示调整。'],
        ['试听并保存', '画布拥有键盘焦点时，按空格试听当前工程，Ctrl+Z / Ctrl+Y 撤销与重做，Ctrl+S 保存到本机草稿箱。'],
      ],
    },
    {
      title: '导入与改编',
      icon: '📥',
      items: [
        ['可导入', '工坊工程 JSON、MIMI/原站 IBE、Guitar Pro（GP3/4/5/GPX/GP/GP7/GP8）、MusicXML（.musicxml/.xml）和 AlphaTex（.tex）。'],
        ['改编曲库谱', '在曲目详情页点「基于此谱改编」。工坊载入可编辑音轨，另建个人副本；原曲库谱不被覆盖。'],
        ['转换提醒', '当前编辑模型面向弦乐 TAB。超出弦数/24 品、额外声部、复杂连音或非弦乐音轨会列出说明；重复提醒会合并，复杂文件会汇总剩余数量。无法完整表示的内容仍留在原始谱面备份中。'],
        ['文件安全', '本机导入的原始文件保存在浏览器 IndexedDB，可在导出菜单下载原件。清理网站数据会清除本机草稿和原件备份。'],
      ],
    },
    {
      title: '预览与导出',
      icon: '🖨️',
      items: [
        ['联动谱面', '工坊同时显示五线谱和六线谱，同一弦/品位对应同一音高；播放时可看光标跟随。'],
        ['文件导出', '工程 JSON 用于以后继续编辑；IBE 是 MIMI 可读的二进制乐谱；GP 为 Guitar Pro 7 文件；TEX 为 AlphaTex 文本。'],
        ['打印分享', 'PNG 导出长图，PDF 按 A4 分页。导出前等待画布完成排版；导出内容来自当前预览。'],
        ['保存范围', '草稿和原件备份只存在当前浏览器，不会自动上传到服务器、同步到账户或公开发布。'],
      ],
    },
    {
      title: '快捷键',
      icon: '⌨️',
      items: [
        ['使用范围', '谱面编辑快捷键仅在交互式乐谱画布拥有键盘焦点时生效。Tab / Shift+Tab 用于页面焦点导航。'],
        ['移动', '←/→ 前后移动一拍；↑/↓ 在当前音轨琴弦之间移动。'],
        ['编辑', 'Alt+1–6 选择全、二、四、八、十六、三十二分音符；. 附点，/ 三连音，R 休止。'],
        ['技巧', 'H 击弦/勾弦，S 滑音，B 推弦，N 泛音，P 闷音，X 死音，V 颤音，L 延音线。'],
        ['结构与恢复', 'Insert 插入小节，Shift+Insert 插入一拍，Delete 删除当前音符，Shift+Delete 删除一拍；Ctrl+S 保存，Ctrl+Z 撤销，Ctrl+Y 重做。'],
      ],
    },
  ];
</script>

<MotionDialog
  open={isOpen}
  labelledBy="studio-guide-title"
  describedBy="studio-guide-description"
  {fallbackFocusSelector}
  backdropClass="items-center p-2 sm:p-5"
  panelClass="w-full max-w-3xl max-h-[calc(100dvh-2rem)] overflow-hidden rounded-3xl border border-[#e2d7c5] bg-[#fdfbf7] shadow-2xl text-[#2c2825]"
  onCloseRequest={() => onClose?.()}
>
  <section class="flex max-h-[calc(100dvh-2rem-2px)] min-h-0 flex-col overflow-hidden">
    <header class="flex shrink-0 items-center justify-between gap-3 border-b border-[#e8dfd2] bg-[#f5efe6] px-5 py-4">
      <div class="min-w-0">
        <p class="text-[10px] font-bold uppercase tracking-[0.22em] text-[#966b1a]">MIMI GUITAR STUDIO</p>
        <h2 id="studio-guide-title" tabindex="-1" data-dialog-initial-focus class="mt-1 font-serif text-xl font-bold">制谱工坊使用指南</h2>
      </div>
      <button
        type="button"
        onclick={onClose}
        aria-label="关闭使用指南"
        class="inline-flex min-h-[44px] min-w-[44px] shrink-0 items-center justify-center rounded-full border border-[#dfd6c7] bg-white text-sm text-[#705c42] transition-colors hover:bg-[#2c2825] hover:text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#c49a45]"
      >
        ✕
      </button>
    </header>

    <div class="min-h-0 flex-1 space-y-5 overflow-y-auto overscroll-contain p-4 sm:p-6">
      <div class="rounded-2xl bg-[#2c2825] p-4 text-[#fbf9f4] sm:p-5">
        <h3 class="font-serif text-base font-bold text-[#fbf9f4]">先录入，再试听，最后导出</h3>
        <p id="studio-guide-description" class="mt-2 text-sm leading-relaxed text-[#e2d7c5]">工坊把音符存成「弦 + 品位 + 时值」。五线谱按音高自动同步，TAB 显示指法位置。每次改动都会更新本机草稿；改编已有曲目时，系统会建立独立副本。</p>
      </div>

      {#each sections as section}
        <section>
          <h3 class="mb-2 flex items-center gap-2 font-serif font-bold text-[#966b1a]"><span aria-hidden="true">{section.icon}</span>{section.title}</h3>
          <div class="grid gap-2 sm:grid-cols-2">
            {#each section.items as item}
              <article class="rounded-2xl border border-[#e8e2d4] bg-white p-3.5">
                <h4 class="text-sm font-bold">{item[0]}</h4>
                <p class="mt-1.5 text-xs leading-relaxed text-[#705c42]">{item[1]}</p>
              </article>
            {/each}
          </div>
        </section>
      {/each}

      <p class="border-t border-[#e8dfd2] pt-3 text-[11px] leading-relaxed text-[#8c7b68]">MIDI 文件导入与五线谱独立音符编辑暂未接入。需要完整保真的场景请保留并下载原始文件，再使用 Guitar Pro 或其他完整制谱软件处理。</p>
    </div>

    <footer class="flex shrink-0 justify-end border-t border-[#e8dfd2] bg-[#f5efe6] px-5 py-3">
      <button
        type="button"
        onclick={onClose}
        class="inline-flex min-h-[44px] items-center justify-center rounded-xl bg-[#2c2825] px-5 text-sm font-bold text-white transition-colors hover:bg-[#403b37] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#c49a45]"
      >
        开始制谱
      </button>
    </footer>
  </section>
</MotionDialog>
