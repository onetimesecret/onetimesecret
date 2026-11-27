// src/shared/composables/useMenuPlacement.ts

import { nextTick, onBeforeUnmount, ref, watch, type Ref } from 'vue';

/**
 * Marks an element the layout fixes to the bottom of the viewport (the
 * workspace footer at md+, the mobile product nav below md). Menus treat the
 * top of the highest visible one as the bottom of the space they can use.
 */
export const BOTTOM_BAR_ATTRIBUTE = 'data-viewport-bottom-bar';

export type MenuPlacement = 'below' | 'above';

export type ElementLike = HTMLElement | { $el?: unknown } | null | undefined;

function toElement(target: ElementLike): HTMLElement | null {
  if (!target) return null;
  if (typeof HTMLElement !== 'undefined' && target instanceof HTMLElement) return target;
  const el = (target as { $el?: unknown }).$el;
  return typeof HTMLElement !== 'undefined' && el instanceof HTMLElement ? el : null;
}

/**
 * The y coordinate, in viewport pixels, where the fixed bottom bars begin:
 * the top of the highest one that is fixed and visible, or the viewport
 * height when none is. A bar in normal flow (the footer below md) does not
 * cover anything and is skipped.
 */
export function viewportBottomBoundary(): number {
  let boundary = window.innerHeight;
  document.querySelectorAll<HTMLElement>(`[${BOTTOM_BAR_ATTRIBUTE}]`).forEach((bar) => {
    if (getComputedStyle(bar).position !== 'fixed') return;
    const rect = bar.getBoundingClientRect();
    if (rect.height > 0 && rect.top < boundary) boundary = rect.top;
  });
  return boundary;
}

/**
 * Whether a menu of `menuHeight` opening from a trigger at `triggerRect`
 * goes below it (the default) or above it. It goes above only when it does
 * not fit between the trigger and the fixed bottom bars and there is more
 * room above the trigger than below.
 */
export function chooseMenuPlacement(
  triggerRect: Pick<DOMRect, 'top' | 'bottom'>,
  menuHeight: number,
  bottomBoundary: number,
  gap = 8
): MenuPlacement {
  const below = bottomBoundary - triggerRect.bottom - gap;
  const above = triggerRect.top - gap;
  return menuHeight > below && above > below ? 'above' : 'below';
}

/**
 * useMenuPlacement - open a dropdown upward when the fixed footer or mobile
 * nav would cover it.
 *
 * The workspace menus sit inside backdrop-blur cards, which are stacking
 * contexts, so no z-index on the menu can lift it above the fixed bars, and
 * raising the page column paints the whole page over them. Opening upward
 * near the bottom keeps the menu inside the visible page instead.
 *
 * The menu is open while its trigger has aria-expanded="true", which the
 * Headless UI Listbox, Menu and Popover buttons set, so callers need no open
 * state of their own. Placement is decided each time the menu opens, after it
 * renders and before the browser paints, from the menu's measured height.
 *
 * @param trigger - the button that opens the menu (element or component)
 * @param menu - the menu panel (element or component)
 */
export function useMenuPlacement(trigger: Ref<ElementLike>, menu: Ref<ElementLike>) {
  const placement = ref<MenuPlacement>('below');
  const isOpen = ref(false);

  const update = () => {
    const triggerEl = toElement(trigger.value);
    const menuEl = toElement(menu.value);
    if (!triggerEl || !menuEl) return;
    placement.value = chooseMenuPlacement(
      triggerEl.getBoundingClientRect(),
      menuEl.offsetHeight,
      viewportBottomBoundary()
    );
  };

  const readExpanded = () => {
    isOpen.value = toElement(trigger.value)?.getAttribute('aria-expanded') === 'true';
  };

  let observer: MutationObserver | null = null;
  watch(
    () => toElement(trigger.value),
    (el) => {
      observer?.disconnect();
      observer = null;
      if (!el || typeof MutationObserver === 'undefined') return;
      observer = new MutationObserver(readExpanded);
      observer.observe(el, { attributes: true, attributeFilter: ['aria-expanded'] });
      readExpanded();
    },
    { flush: 'post', immediate: true }
  );
  onBeforeUnmount(() => observer?.disconnect());

  watch(isOpen, async (open) => {
    if (!open) {
      placement.value = 'below';
      return;
    }
    await nextTick();
    update();
  });

  return { placement, isOpen, update };
}
