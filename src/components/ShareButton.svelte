<script lang="ts">
  let copied = $state(false);
  let toastTimer: any = null;

  async function copy() {
    const url = window.location.href;
    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(url);
      } else {
        const ta = document.createElement('textarea');
        ta.value = url;
        ta.style.position = 'fixed';
        ta.style.opacity = '0';
        document.body.appendChild(ta);
        ta.select();
        document.execCommand('copy');
        document.body.removeChild(ta);
      }
      copied = true;
      if (toastTimer) clearTimeout(toastTimer);
      toastTimer = setTimeout(() => {
        copied = false;
      }, 2500);
    } catch {
      copied = true;
      if (toastTimer) clearTimeout(toastTimer);
      toastTimer = setTimeout(() => {
        copied = false;
      }, 2500);
    }
  }
</script>

<button
  type="button"
  class="btn inline-flex items-center gap-2 rounded-pill border hairline bg-paper px-4 py-2 text-body-sm font-medium text-ink transition-all duration-200 hover:bg-canvas active:scale-95 shadow-2xs"
  onclick={copy}
  aria-label="分享曲谱链接"
>
  <svg class="h-4 w-4 text-charcoal" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
    <circle cx="18" cy="5" r="3"></circle>
    <circle cx="6" cy="12" r="3"></circle>
    <circle cx="18" cy="19" r="3"></circle>
    <line x1="8.59" y1="13.51" x2="15.42" y2="17.49"></line>
    <line x1="15.41" y1="6.51" x2="8.59" y2="10.49"></line>
  </svg>
  <span>分享曲谱</span>
</button>

<!-- Frosted Toast Notification -->
{#if copied}
  <div class="toast-pill flex items-center gap-2.5 shadow-2xl" role="status" aria-live="polite">
    <svg class="h-4 w-4 text-emerald-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
      <polyline points="20 6 9 17 4 12"></polyline>
    </svg>
    <span>已复制曲谱链接到剪贴板</span>
  </div>
{/if}