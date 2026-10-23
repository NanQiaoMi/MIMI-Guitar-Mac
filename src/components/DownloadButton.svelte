<script lang="ts">
  let { tabId = '' }: { tabId?: string } = $props();
  let state = $state<'idle' | 'downloading' | 'error'>('idle');

  async function download() {
    state = 'downloading';
    try {
      const res = await fetch(`/api/tabs/${tabId}/download`, { credentials: 'same-origin' });
      if (res.status === 401) {
        location.href = `/login?returnUrl=${encodeURIComponent(location.pathname)}`;
        return;
      }
      if (!res.ok) throw new Error('下载失败');
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${tabId}.ibe`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      state = 'idle';
    } catch {
      state = 'error';
    }
  }
</script>

<button
  type="button"
  class="btn btn-signal inline-flex items-center gap-1.5 rounded-pill px-4 py-2 text-body-sm font-medium"
  onclick={download}
  disabled={state === 'downloading'}
>
  <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
    <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
    <polyline points="7 10 12 15 17 10"></polyline>
    <line x1="12" y1="15" x2="12" y2="3"></line>
  </svg>
  <span>{state === 'downloading' ? '下载中…' : state === 'error' ? '下载失败' : '免费下载'}</span>
</button>