// src/apps/admin/components/kit/jsonViewerKeys.ts

/**
 * Shared types threaded from {@link JsonViewer} down through its recursive
 * {@link JsonViewerNode} children.
 *
 * State is passed by PROPS (not provide/inject): the tree is small, the drilling
 * is one prop deep per level, and it keeps every node unit-testable without a
 * provider wrapper.
 */

/**
 * A one-way expand/collapse broadcast. The toolbar bumps `version` (and sets the
 * target `expanded`); each container node watches `version` and snaps to
 * `expanded`, while still allowing local per-node toggling afterwards.
 */
export interface JsonViewerSignal {
  version: number;
  expanded: boolean;
}
