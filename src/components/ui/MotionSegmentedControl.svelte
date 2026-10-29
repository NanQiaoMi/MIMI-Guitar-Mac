<script lang="ts">
  export interface MotionSegmentOption {
    value: string;
    label: string;
    disabled?: boolean;
  }

  interface Props {
    value: string;
    options: MotionSegmentOption[];
    onChange: (value: string) => void;
    label: string;
    id?: string;
  }

  let { value, options, onChange, label, id }: Props = $props();
  let focusedIndex = $state<number | null>(null);
  let optionButtons: Array<HTMLButtonElement | undefined> = [];

  // Invalid controlled values get a stable visual and keyboard fallback without
  // firing onChange during render. If every option is disabled, there is no stop.
  let selectedIndex = $derived.by(() => {
    const exactIndex = options.findIndex((option) => option.value === value && !option.disabled);
    return exactIndex >= 0 ? exactIndex : options.findIndex((option) => !option.disabled);
  });

  let tabStopIndex = $derived.by(() => {
    if (focusedIndex !== null && options[focusedIndex] && !options[focusedIndex].disabled) {
      return focusedIndex;
    }
    return selectedIndex;
  });

  let optionCount = $derived(Math.max(options.length, 1));
  let selectedOffset = $derived(selectedIndex < 0 ? '0%' : `calc(${selectedIndex * 100}% + ${selectedIndex * 2}px)`);

  function selectIndex(index: number) {
    const option = options[index];
    if (!option || option.disabled) return;

    focusedIndex = index;
    if (option.value !== value) onChange(option.value);
  }

  function moveFocus(index: number, event: KeyboardEvent) {
    const enabledIndices = options.reduce<number[]>((indices, option, optionIndex) => {
      if (!option.disabled) indices.push(optionIndex);
      return indices;
    }, []);
    if (enabledIndices.length === 0) return;

    let nextIndex: number | null = null;
    if (event.key === 'Home') {
      nextIndex = enabledIndices[0];
    } else if (event.key === 'End') {
      nextIndex = enabledIndices[enabledIndices.length - 1];
    } else if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
      const direction = window.getComputedStyle(event.currentTarget as Element).direction;
      const visualStep = event.key === 'ArrowRight' ? 1 : -1;
      const step = direction === 'rtl' ? -visualStep : visualStep;
      const currentPosition = Math.max(0, enabledIndices.indexOf(index));
      nextIndex = enabledIndices[(currentPosition + step + enabledIndices.length) % enabledIndices.length];
    } else {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    if (nextIndex === null) return;

    optionButtons[nextIndex]?.focus();
    selectIndex(nextIndex);
  }
</script>

{#if options.length > 0}
  <div
    {id}
    class="motion-segmented-control"
    role="radiogroup"
    aria-label={label}
    aria-orientation="horizontal"
    style={`--motion-option-count:${optionCount};--motion-selected-offset:${selectedOffset}`}
  >
    {#if selectedIndex >= 0}
      <span class="motion-segmented-control__track" aria-hidden="true">
        <span class="motion-segmented-control__indicator"></span>
      </span>
    {/if}

    {#each options as option, index (option.value)}
      <button
        bind:this={optionButtons[index]}
        type="button"
        role="radio"
        aria-label={option.label}
        aria-checked={index === selectedIndex}
        aria-disabled={Boolean(option.disabled)}
        disabled={Boolean(option.disabled)}
        tabindex={!option.disabled && index === tabStopIndex ? 0 : -1}
        class="motion-segmented-control__option"
        class:is-selected={index === selectedIndex}
        onfocus={() => {
          if (!option.disabled) focusedIndex = index;
        }}
        onclick={() => selectIndex(index)}
        onkeydown={(event) => moveFocus(index, event)}
      >
        <span>{option.label}</span>
      </button>
    {/each}
  </div>
{/if}

<style>
  .motion-segmented-control {
    --motion-option-count: 1;
    position: relative;
    display: inline-grid;
    grid-template-columns: repeat(var(--motion-option-count), minmax(0, 1fr));
    gap: 2px;
    max-width: 100%;
    padding: 3px;
    border: 1px solid #ded3bd;
    border-radius: 999px;
    background: #f4eddf;
    box-shadow: inset 0 1px 2px rgb(74 55 30 / 7%);
    isolation: isolate;
  }

  .motion-segmented-control__track {
    position: absolute;
    z-index: 0;
    inset: 3px;
    display: grid;
    grid-template-columns: repeat(var(--motion-option-count), minmax(0, 1fr));
    gap: 2px;
    overflow: hidden;
    border-radius: inherit;
    pointer-events: none;
  }

  .motion-segmented-control__indicator {
    grid-row: 1;
    grid-column: 1;
    border: 1px solid rgb(170 135 78 / 28%);
    border-radius: 999px;
    background: linear-gradient(180deg, #fffdf8 0%, #f7f0e2 100%);
    box-shadow: 0 1px 3px rgb(74 55 30 / 12%), inset 0 1px 0 rgb(255 255 255 / 92%);
    transform: translateX(var(--motion-selected-offset, 0%));
    transition: transform var(--motion-duration-control, 200ms) var(--motion-ease-settle, cubic-bezier(0.22, 1, 0.36, 1));
  }

  .motion-segmented-control:dir(rtl) .motion-segmented-control__indicator {
    transform: translateX(calc(0% - var(--motion-selected-offset, 0%)));
  }

  .motion-segmented-control__option {
    position: relative;
    z-index: 1;
    display: inline-flex;
    min-width: 44px;
    min-height: 44px;
    align-items: center;
    justify-content: center;
    padding: 0.5rem clamp(0.45rem, 2vw, 0.9rem);
    border: 0;
    border-radius: 999px;
    background: transparent;
    color: #6f5b3f;
    font: inherit;
    font-size: 0.875rem;
    line-height: 1.2;
    text-align: center;
    overflow-wrap: anywhere;
    cursor: pointer;
    transition: color var(--motion-duration-micro, 120ms) var(--motion-ease-standard, cubic-bezier(0.2, 0, 0, 1));
  }

  .motion-segmented-control__option.is-selected {
    color: #382d1e;
    font-weight: 600;
  }

  .motion-segmented-control__option:hover:not(:disabled) {
    color: #3e2f1d;
  }

  .motion-segmented-control__option:focus-visible {
    z-index: 2;
    outline: 2px solid #3988ad;
    outline-offset: -2px;
  }

  .motion-segmented-control__option:disabled {
    color: #a79b89;
    cursor: not-allowed;
  }

  /* Keep the selected indicator at its resolved transform while avoiding spatial travel in gentle mode. */
  :global(html[data-motion='gentle']) .motion-segmented-control__indicator,
  :global(html[data-motion='off']) .motion-segmented-control__indicator {
    transition-property: none;
  }

  :global(html[data-motion='off']) .motion-segmented-control__option {
    transition: none;
  }

  @media (prefers-reduced-motion: reduce) {
    .motion-segmented-control__indicator,
    .motion-segmented-control__option {
      transition-duration: 0ms !important;
    }
  }
</style>
