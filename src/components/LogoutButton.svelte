<script lang="ts">
  export let className = 'btn';

  let busy = false;
  async function logout() {
    busy = true;
    try {
      await fetch('/api/auth/logout', { method: 'POST' });
    } catch {
      /* ignore */
    }
    location.href = '/';
  }
</script>

<button onclick={logout} disabled={busy} class={className}>{busy ? '退出中…' : '退出登录'}</button>
