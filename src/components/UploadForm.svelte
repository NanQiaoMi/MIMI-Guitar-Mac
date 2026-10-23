<script lang="ts">
  export let category = 'guitar';

  let file: File | null = null;
  let title = '';
  let error = '';
  let info = '';
  let uploading = false;

  function onFile(e: Event) {
    const input = e.target as HTMLInputElement;
    file = input.files?.[0] ?? null;
    error = '';
  }

  async function submit(e: Event) {
    e.preventDefault();
    if (!file) {
      error = '请选择 Guitar Pro 文件';
      return;
    }
    uploading = true;
    error = '';
    info = '';
    try {
      const fd = new FormData();
      fd.append('file', file);
      fd.append('category', category);
      fd.append('title', title);
      const res = await fetch('/api/upload', { method: 'POST', body: fd });
      const data = await res.json();
      if (!res.ok) {
        error = data.error ?? '上传失败';
        return;
      }
      info = '上传成功（' + data.title + '），已进入待审核状态。可在「创作中心」查看或模拟审核。';
      file = null;
      title = '';
      (document.querySelector('input[type=file]') as HTMLInputElement).value = '';
    } catch {
      error = '网络错误，请稍后重试';
    } finally {
      uploading = false;
    }
  }
</script>

<form onsubmit={submit} class="space-y-5">
  {#if error}
    <p class="text-body-sm text-danger">{error}</p>
  {/if}
  {#if info}
    <p class="text-body-sm text-cerulean">{info}</p>
  {/if}
  <div>
    <label class="text-caption text-ash">选择 Guitar Pro 文件（.gp3 / .gp4 / .gp5 / .gpx / .gp）</label>
    <input type="file" accept=".gp3,.gp4,.gp5,.gpx,.gp" onchange={onFile} class="mt-2 block w-full text-body-sm" />
  </div>
  <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
    <div>
      <label class="text-caption text-ash">分类</label>
      <select bind:value={category} class="hairline mt-1 w-full rounded-btn bg-paper px-3 py-2 text-body-sm outline-none focus:border-signal">
        <option value="guitar">吉他</option>
        <option value="ukulele">尤克里里</option>
      </select>
    </div>
    <div>
      <label class="text-caption text-ash">标题（可选，默认取曲谱内标题）</label>
      <input bind:value={title} type="text" placeholder="曲名" class="hairline mt-1 w-full rounded-btn bg-paper px-3 py-2 text-body-sm outline-none focus:border-signal" />
    </div>
  </div>
  <button type="submit" disabled={uploading} class="btn btn-signal w-full py-2.5">
    {uploading ? '上传解析中…' : '上传乐谱'}
  </button>
</form>
