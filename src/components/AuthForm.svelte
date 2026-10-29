<script lang="ts">
  import { onMount } from 'svelte';

  export let mode: 'login' | 'register' = 'login';

  let account = '';
  let password = '';
  let nickname = '';
  let error = '';
  let loading = false;
  let returnUrl = '/account/0';

  onMount(() => {
    const p = new URLSearchParams(location.search).get('returnUrl');
    if (p && p.startsWith('/')) returnUrl = p;
  });

  const inputCls = 'hairline w-full rounded-btn bg-paper px-4 py-2.5 text-body-sm outline-none focus:border-signal';

  async function submit(e: Event) {
    e.preventDefault();
    error = '';
    if (!account || !password) {
      error = '请填写账号与密码';
      return;
    }
    if (mode === 'register' && password.length < 6) {
      error = '密码至少 6 位';
      return;
    }
    loading = true;
    try {
      const res = await fetch(mode === 'login' ? '/api/auth/login' : '/api/auth/register', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ account, password, nickname }),
      });
      const data = await res.json();
      if (!res.ok) {
        error = data.error ?? '操作失败';
        return;
      }
      location.href = returnUrl;
    } catch {
      error = '网络错误，请稍后重试';
    } finally {
      loading = false;
    }
  }
</script>

<form onsubmit={submit} class="space-y-4">
  {#if error}
    <p class="text-body-sm text-danger" role="alert">{error}</p>
  {/if}
  {#if mode === 'register'}
    <label class="block">
      <span class="text-caption text-ash">昵称（可选）</span>
      <input bind:value={nickname} type="text" autocomplete="nickname" placeholder="昵称（可选）" class={'mt-1 ' + inputCls} />
    </label>
  {/if}
  <label class="block">
    <span class="text-caption text-ash">手机号或邮箱</span>
    <input bind:value={account} type="text" autocomplete="username" placeholder="手机号或邮箱" class={'mt-1 ' + inputCls} />
  </label>
  <label class="block">
    <span class="text-caption text-ash">密码</span>
    <input bind:value={password} type="password" autocomplete={mode === 'login' ? 'current-password' : 'new-password'} placeholder="密码（至少 6 位）" class={'mt-1 ' + inputCls} />
  </label>
  <button type="submit" disabled={loading} class="btn btn-signal w-full py-2.5">
    {loading ? '提交中…' : mode === 'login' ? '登录' : '注册'}
  </button>
  <p class="text-center text-caption text-ash">
    {#if mode === 'login'}
      <a href="/register" class="text-signal hover:opacity-70">还没有账号？去注册</a>
      <span class="mx-2">·</span>
      <a href="/account/reset" class="text-signal hover:opacity-70">忘记密码</a>
    {:else}
      <a href="/login" class="text-signal hover:opacity-70">已有账号？去登录</a>
    {/if}
  </p>
</form>