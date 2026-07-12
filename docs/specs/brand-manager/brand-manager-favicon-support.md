since: 2026-07-11
---

The logo now uses a staged upload modal instead of committing the instant a file is picked.

"Favicon reuse is now pure props wiring" means: if you later want the same staged-upload flow for a domain's favicon, you shouldn't need to write any new modal logic — you'd just render the existing ImageUploadModal again and pass it a different set of prop values.

The reason is how I built the modal: it knows nothing about logos specifically. All the logo-vs-favicon differences are supplied by the parent through props:

- currentImage — the persisted image to show as baseline
- title, hint, saveLabel, removeLabel — the caller-supplied (already-translated) strings
- accept, maxSizeBytes — validation config
- onSave(file) / onRemove() — the async commit handlers the parent provides

The modal's internals (staging the file, local preview via fileToDataUrl, validation, the confirm-CTA commit, the "stay open on failure" behavior) are all image-agnostic. So a favicon control would be roughly:

vue
<ImageUploadModal
  :is-open="isFaviconModalOpen"
  :current-image="faviconImage"
  :title="t('...favicon_title')"
  :save-label="t('...save_favicon')"
  :on-save="onFaviconUpload"
  :on-remove="onFaviconRemove"
  @close="isFaviconModalOpen = false" />

"Pure props wiring" = you compose it by passing props, not by editing the modal or writing new upload/staging code.

One caveat I flagged in the same message: this is front-end readiness only. There are no favicon API endpoints yet — brandStore currently exposes only uploadLogo/removeLogo/fetchLogo. So before favicon reuse is actually functional, someone would need to add favicon store actions (and the backend endpoints behind them) to supply those onSave/onRemove handlers. The modal itself won't need changes; the missing piece is the persistence layer it delegates to.
