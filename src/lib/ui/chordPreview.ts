export interface ChordPreviewRect {
  left: number;
  right: number;
  top: number;
  bottom: number;
  width: number;
  height: number;
}

export interface ChordPreviewAnchor {
  getBoundingClientRect(): ChordPreviewRect;
  contains?(target: Node): boolean;
  isConnected?: boolean;
}

export interface ChordPreviewTarget {
  anchor: ChordPreviewAnchor;
  name: string;
  svg: string | null;
  hasDiagram: boolean;
  accessibleName: string;
  unavailableMessage: string | null;
}

export interface ChordPreviewContent {
  name: string;
  svg: string | null;
  hasDiagram: boolean;
  accessibleName: string;
  unavailableMessage: string | null;
}

export interface ChordPreviewContext {
  viewMode: string;
  visibleItemsSignature: string;
}

export interface ChordPreviewState {
  hovered: ChordPreviewTarget | null;
  focused: ChordPreviewTarget | null;
  pinned: ChordPreviewTarget | null;
}

export type ChordPreviewAction =
  | { type: 'hover'; target: ChordPreviewTarget }
  | { type: 'focus'; target: ChordPreviewTarget }
  | { type: 'activate'; target: ChordPreviewTarget }
  | { type: 'leave'; anchor: ChordPreviewAnchor }
  | { type: 'blur'; anchor: ChordPreviewAnchor }
  | { type: 'dismiss' };

export interface ChordPopoverSize {
  width: number;
  height: number;
}

export interface ChordPopoverViewport {
  width: number;
  height: number;
}

export interface ChordPopoverPosition {
  left: number;
  top: number;
  /** Left edge of the 8px pointer, measured inside the popover. */
  arrowLeft: number;
  side: 'above' | 'below';
}

export interface ChordPreviewListenerOptions {
  getActive(): ChordPreviewTarget | null;
  getPopover(): { contains?(target: Node): boolean } | null;
  dismiss(): void;
  reposition(): void;
}

export function createChordPreviewState(): ChordPreviewState {
  return { hovered: null, focused: null, pinned: null };
}

export function resolveChordPreview(state: ChordPreviewState): ChordPreviewTarget | null {
  return state.pinned ?? state.focused ?? state.hovered;
}

export function chordPreviewAccessibleName(name: string, hasDiagram: boolean): string {
  return hasDiagram
    ? `预览${name}和弦指法图`
    : `查看${name}和弦指法图收录情况`;
}

export function createChordPreviewContent(name: string, svg: string | null): ChordPreviewContent {
  const hasDiagram = typeof svg === 'string' && svg.length > 0;
  return {
    name,
    svg: hasDiagram ? svg : null,
    hasDiagram,
    accessibleName: chordPreviewAccessibleName(name, hasDiagram),
    unavailableMessage: hasDiagram ? null : '暂未收录此和弦指法图',
  };
}

export function createChordPreviewTarget(
  anchor: ChordPreviewAnchor,
  name: string,
  svg: string | null,
): ChordPreviewTarget {
  return { anchor, ...createChordPreviewContent(name, svg) };
}

/** Reconcile pin/focus/hover against the view and item set that owns the anchor. */
export function reconcileChordPreviewContext(
  state: ChordPreviewState,
  previous: ChordPreviewContext,
  current: ChordPreviewContext,
  isAnchorAvailable: (target: ChordPreviewTarget) => boolean,
): ChordPreviewState {
  const active = resolveChordPreview(state);
  if (!active) return state;
  const contextChanged = previous.viewMode !== current.viewMode
    || previous.visibleItemsSignature !== current.visibleItemsSignature;
  return contextChanged || current.viewMode !== 'gallery' || !isAnchorAvailable(active)
    ? createChordPreviewState()
    : state;
}

/**
 * Keep hover, keyboard focus, and explicit click activation independent so a
 * mouse leave cannot dismiss a focused or pinned preview.
 */
export function updateChordPreviewState(
  state: ChordPreviewState,
  action: ChordPreviewAction,
): ChordPreviewState {
  if (action.type === 'dismiss') return createChordPreviewState();

  if (action.type === 'hover') return { ...state, hovered: action.target };
  if (action.type === 'focus') {
    return {
      ...state,
      focused: action.target,
      pinned: state.pinned?.anchor === action.target.anchor ? state.pinned : null,
    };
  }

  if (action.type === 'leave') {
    return state.hovered?.anchor === action.anchor ? { ...state, hovered: null } : state;
  }

  if (action.type === 'blur') {
    return state.focused?.anchor === action.anchor ? { ...state, focused: null } : state;
  }

  if (state.pinned?.anchor === action.target.anchor) {
    // Clear hover/focus for the toggled anchor too, otherwise its active source
    // would immediately reveal the preview again after the pinned source closes.
    return {
      hovered: state.hovered?.anchor === action.target.anchor ? null : state.hovered,
      focused: state.focused?.anchor === action.target.anchor ? null : state.focused,
      pinned: null,
    };
  }

  // The first click after focus/hover pins the already-visible preview. It must
  // not toggle it closed; the next click on the same anchor dismisses it.
  return { ...state, pinned: action.target };
}

/** Attach only page-local listeners; the returned disposer removes every listener. */
export function attachChordPreviewListeners(
  options: ChordPreviewListenerOptions,
  environment: { document?: Document | null; window?: Window | null } = {},
): () => void {
  const doc = environment.document === undefined
    ? (typeof document === 'undefined' ? null : document)
    : environment.document;
  const view = environment.window === undefined
    ? (typeof window === 'undefined' ? null : window)
    : environment.window;
  if (!doc || !view) return () => undefined;

  const handlePointerDown = (event: PointerEvent) => {
    const active = options.getActive();
    if (!active) return;
    const target = event.target;
    if (!(target instanceof Node)) {
      options.dismiss();
      return;
    }
    if (active.anchor.contains?.(target) || options.getPopover()?.contains?.(target)) return;
    options.dismiss();
  };
  const handleKeydown = (event: KeyboardEvent) => {
    if (!options.getActive() || event.key !== 'Escape') return;
    event.preventDefault();
    options.dismiss();
  };
  const handleViewportChange = () => {
    if (options.getActive()) options.reposition();
  };

  doc.addEventListener('pointerdown', handlePointerDown, true);
  doc.addEventListener('keydown', handleKeydown);
  doc.addEventListener('scroll', handleViewportChange, true);
  view.addEventListener('resize', handleViewportChange);
  return () => {
    doc.removeEventListener('pointerdown', handlePointerDown, true);
    doc.removeEventListener('keydown', handleKeydown);
    doc.removeEventListener('scroll', handleViewportChange, true);
    view.removeEventListener('resize', handleViewportChange);
  };
}

function finite(value: number): number {
  return Number.isFinite(value) ? value : 0;
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(maximum, Math.max(minimum, value));
}

/** Position from measured dimensions, preferring above while it fits and flipping below near the top edge. */
export function positionChordPopover(
  anchor: ChordPreviewRect,
  popover: ChordPopoverSize,
  viewport: ChordPopoverViewport,
  options: { gap?: number; margin?: number } = {},
): ChordPopoverPosition {
  const gap = Math.max(0, finite(options.gap ?? 8));
  const margin = Math.max(0, finite(options.margin ?? 8));
  const viewportWidth = Math.max(0, finite(viewport.width));
  const viewportHeight = Math.max(0, finite(viewport.height));
  const popoverWidth = Math.max(0, finite(popover.width));
  const popoverHeight = Math.max(0, finite(popover.height));
  const leftLimit = Math.max(margin, viewportWidth - margin - popoverWidth);
  const left = clamp(
    finite(anchor.left) + (finite(anchor.width) - popoverWidth) / 2,
    margin,
    leftLimit,
  );

  const aboveSpace = Math.max(0, finite(anchor.top) - margin - gap);
  const belowSpace = Math.max(0, viewportHeight - margin - gap - finite(anchor.bottom));
  const fitsAbove = aboveSpace >= popoverHeight;
  const fitsBelow = belowSpace >= popoverHeight;
  const side: ChordPopoverPosition['side'] = fitsAbove || !fitsBelow && aboveSpace >= belowSpace
    ? 'above'
    : 'below';
  const requestedTop = side === 'above'
    ? finite(anchor.top) - gap - popoverHeight
    : finite(anchor.bottom) + gap;
  const topLimit = Math.max(margin, viewportHeight - margin - popoverHeight);
  const arrowLeft = clamp(
    finite(anchor.left) + finite(anchor.width) / 2 - left - 4,
    4,
    Math.max(4, popoverWidth - 12),
  );

  return {
    left,
    top: clamp(requestedTop, margin, topLimit),
    arrowLeft,
    side,
  };
}
