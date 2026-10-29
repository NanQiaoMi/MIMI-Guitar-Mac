<script lang="ts">
  import { onMount } from 'svelte';
  import { startMotionPreferenceRuntime } from '../../lib/ui/motionPreferences.ts';

  onMount(() => {
    const stopMotionPreferenceRuntime = startMotionPreferenceRuntime();
    const root = document.documentElement;

    const syncPageVisibility = () => {
      if (document.hidden) root.setAttribute('data-page-hidden', '');
      else root.removeAttribute('data-page-hidden');
    };

    document.addEventListener('visibilitychange', syncPageVisibility);
    syncPageVisibility();

    return () => {
      document.removeEventListener('visibilitychange', syncPageVisibility);
      root.removeAttribute('data-page-hidden');
      stopMotionPreferenceRuntime();
    };
  });
</script>
