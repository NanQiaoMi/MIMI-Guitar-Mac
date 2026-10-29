<script lang="ts">
  let { code = '', language = 'typescript', title = '' } = $props<{
    code: string;
    language?: string;
    title?: string;
  }>();

  let copied = $state(false);

  async function copyCode() {
    try {
      await navigator.clipboard.writeText(code);
      copied = true;
      setTimeout(() => (copied = false), 2000);
    } catch {
      const ta = document.createElement('textarea');
      ta.value = code;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
      copied = true;
      setTimeout(() => (copied = false), 2000);
    }
  }
</script>

<div class="overflow-hidden rounded-[16px] border border-[#e5e5e5] bg-[#0a0a0a] text-[#f5f5f5] shadow-sm">
  <div class="flex items-center justify-between border-b border-[#2c2c2c] px-4 py-2.5 bg-[#171717]/80">
    <div class="flex items-center gap-2">
      <div class="flex items-center gap-1.5">
        <span class="h-2.5 w-2.5 rounded-full bg-[#e7000b]/80"></span>
        <span class="h-2.5 w-2.5 rounded-full bg-[#eab308]/80"></span>
        <span class="h-2.5 w-2.5 rounded-full bg-[#22c55e]/80"></span>
      </div>
      {#if title}
        <span class="ml-2 font-mono text-xs text-[#a3a3a3]">{title}</span>
      {:else}
        <span class="ml-2 font-mono text-xs uppercase text-[#a3a3a3]">{language}</span>
      {/if}
    </div>
    <button
      type="button"
      onclick={copyCode}
      class="inline-flex items-center gap-1.5 rounded-[12px] border border-[#444141] bg-[#2c2c2c]/60 px-2.5 py-1 text-xs font-medium text-[#dee2de] transition hover:bg-[#444141] hover:text-white"
    >
      {#if copied}
        <svg class="h-3.5 w-3.5 text-[#22c55e]" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
          <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
        </svg>
        <span class="text-[#22c55e]">已复制</span>
      {:else}
        <svg class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
        </svg>
        <span>复制代码</span>
      {/if}
    </button>
  </div>
  <pre class="overflow-x-auto p-4 font-mono text-xs leading-relaxed text-[#e5e5e5]"><code>{code}</code></pre>
</div>
