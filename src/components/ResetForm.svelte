<script lang="ts">
  let phone = '';
  let code = '';
  let password = '';
  let error = '';
  let info = '';
  let loading = false;
  let sending = false;

  const inputCls = 'hairline w-full rounded-btn bg-paper px-4 py-2.5 text-body-sm outline-none focus:border-signal';

  async function sendCode() {
    error = '';
    if (!/^1d{10}$/.test(phone)) {
      error = '请输入正确的手机号';
      return;
    }
    sending = true;
    try {
      const res = await fetch('/api/auth/send-code', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ phone }),
      });
      const data = await res.json();
      if (!res.ok) {
        error = data.error ?? '发送失败';
        return;
      }
      info = '验证码已发送（本地 mock）：' + data.code;
    } catch {
      error = '网络错误，请稍后重试';
    } finally {
      sending = false;
    }
  }

  async function submit(e: Event) {
    e.preventDefault();
    error = '';
    if (password.length < 6) {
      error = '新密码至少 6 位';
      return;
    }
    loading = true;
    try {
      const res = await fetch('/api/auth/reset', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ phone, code, password }),
      });
      const data = await res.json();
      if (!res.ok) {
        error = data.error ?? '重置失败';
        return;
      }
      location.href = '/login';
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
  {#if info}
    <p class="text-body-sm text-cerulean">{info}</p>
  {/if}
  <label class="block">
    <span class="text-caption text-ash">注册时使用的手机号</span>
    <input bind:value={phone} type="tel" autocomplete="tel" placeholder="手机号" class={'mt-1 ' + inputCls} />
  </label>
  <div class="flex gap-2">
    <label class="block flex-1">
      <span class="text-caption text-ash">短信验证码</span>
      <input bind:value={code} type="text" autocomplete="one-time-code" placeholder="验证码" class={'mt-1 ' + inputCls} />
    </label>
    <button type="button" onclick={sendCode} disabled={sending} class="btn mt-[26px] shrink-0">{sending ? '发送中…' : '获取验证码'}</button>
  </div>
  <label class="block">
    <span class="text-caption text-ash">新密码</span>
    <input bind:value={password} type="password" autocomplete="new-password" placeholder="新密码（至少 6 位）" class={'mt-1 ' + inputCls} />
  </label>
  <button type="submit" disabled={loading} class="btn btn-signal w-full py-2.5">{loading ? '提交中…' : '重置密码'}</button>
  <p class="text-center text-caption text-ash">
    <a href="/login" class="text-signal hover:opacity-70">返回登录</a>
  </p>
</form>