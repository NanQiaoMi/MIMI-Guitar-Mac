<script lang="ts">
  export let initial: any[] = [];

  let items = initial;

  async function review(id: string, action: string) {
    const res = await fetch('/api/upload/' + id + '/review', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ action }),
    });
    if (!res.ok) return;
    const data = await res.json();
    items = items.map((x) => (x.id === id ? { ...x, status: data.status, tabId: data.tabId ?? x.tabId } : x));
  }

  function statusText(s: string) {
    return s === 'approved' ? '已通过' : s === 'rejected' ? '已拒绝' : '审核中';
  }
</script>

<ul class="grid grid-cols-1 gap-3">
  {#each items as u (u.id)}
    <li class="card flex items-center gap-4 p-4">
      {#if u.screenshotUrl}
        <img src={u.screenshotUrl} alt={u.title} class="h-16 w-24 shrink-0 rounded hairline object-cover" />
      {/if}
      <div class="min-w-0 flex-1">
        <p class="truncate font-medium">{u.title} <span class="text-ash font-normal">- {u.artist}</span></p>
        <p class="mt-1 truncate text-caption text-ash">
          {u.fileName} · {statusText(u.status)} · {new Date(u.createdAt).toLocaleDateString()}
        </p>
        {#if u.status === 'approved' && u.tabId}
          <a href={'/tabs/' + u.tabId} class="mt-1 inline-block text-caption text-signal hover:opacity-70">查看曲谱 →</a>
        {/if}
      </div>
      {#if u.status === 'pending'}
        <div class="flex shrink-0 flex-col gap-2 sm:flex-row">
          <button onclick={() => review(u.id, 'approve')} class="btn btn-signal">模拟通过</button>
          <button onclick={() => review(u.id, 'reject')} class="btn">拒绝</button>
        </div>
      {/if}
    </li>
  {/each}
</ul>