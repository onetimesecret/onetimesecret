# docs/specs/qa/visual-regressions/qa-visual-regressions-backstopjs.md

---

BackstopJS is a visual regression tool that captures screenshots of customer-visible pages with a headless browser and compares them against approved reference images. Here is a practical way to incorporate it into a web development workflow.

## 1. Install and initialize

Install BackstopJS in your project:

```bash
npm install --save-dev backstopjs
```

Initialize the default configuration:

```bash
npx backstop init
```

This creates `backstop.json` and a `backstop_data/` directory with folders for reference images, test images, and HTML reports [^1].

## 2. Configure customer-visible pages

Edit `backstop.json` to list the pages and viewports you want to protect. A minimal example:

```json
{
  "id": "customer_pages",
  "viewports": [
    { "label": "desktop", "width": 1280, "height": 800 },
    { "label": "tablet", "width": 768, "height": 1024 },
    { "label": "mobile", "width": 375, "height": 667 }
  ],
  "scenarios": [
    {
      "label": "homepage",
      "url": "https://staging.example.com/",
      "referenceUrl": "https://www.example.com/",
      "readySelector": "body.loaded",
      "hideSelectors": [".dynamic-ad", ".live-chat"],
      "misMatchThreshold": 0.1
    },
    {
      "label": "product-detail",
      "url": "https://staging.example.com/product/123",
      "referenceUrl": "https://www.example.com/product/123",
      "selectors": ["main"],
      "readySelector": "[data-testid='product-gallery']"
    }
  ],
  "paths": {
    "bitmaps_reference": "backstop_data/bitmaps_reference",
    "bitmaps_test": "backstop_data/bitmaps_test",
    "html_report": "backstop_data/html_report",
    "ci_report": "backstop_data/ci_report"
  },
  "report": ["browser", "CI"],
  "engine": "playwright",
  "engineOptions": {
    "browser": "chromium"
  },
  "asyncCaptureLimit": 5,
  "asyncCompareLimit": 50
}
```

Key scenario properties:

| Property                            | Purpose                                                                                |
| ----------------------------------- | -------------------------------------------------------------------------------------- |
| `url`                               | Page to test, typically staging or a preview build                                     |
| `referenceUrl`                      | Optional production or known-good baseline for comparison                              |
| `readySelector`                     | Wait for a DOM element before capturing; preferred over fixed delays                   |
| `delay`                             | Fixed wait time in ms; use only as a last resort because it makes tests slow and flaky |
| `hideSelectors` / `removeSelectors` | Hide or remove dynamic elements such as ads, chat widgets, or timestamps               |
| `selectors`                         | Capture only specific DOM elements instead of the full document                        |
| `misMatchThreshold`                 | Allowed percentage of differing pixels before failure                                  |
| `requireSameDimensions`             | Fail if the screenshot dimensions change                                               |

[^1][^2]

## 3. Establish baselines

Generate the first set of approved reference screenshots:

```bash
npx backstop reference
```

Commit the generated `backstop_data/bitmaps_reference/` folder so the whole team shares the same baseline. Ignore temporary output:

```gitignore
backstop_data/bitmaps_test/
backstop_data/html_report/
backstop_data/ci_report/
```

[^1][^2]

## 4. Run tests in development and CI

After any UI change, compare the current state against the baseline:

```bash
npx backstop test
```

BackstopJS opens an HTML report showing any pixel differences. If the changes are intentional, promote the new screenshots to reference:

```bash
npx backstop approve
```

For CI, use the `CI` report to produce JUnit XML and rely on the exit code (`0` for pass, `1` for fail):

```bash
npx backstop test --config=backstop.json
```

[^1]

## 5. Reduce flakiness

Customer pages often contain dynamic content. Recommended mitigations:

- **Wait for readiness** with `readySelector` instead of arbitrary `delay` [^2].
- **Hide or remove** dynamic elements such as ads, carousels, live chat, or user-generated timestamps with `hideSelectors` / `removeSelectors` [^1].
- **Stub data** so product listings, reviews, or recommendations render identically on every run.
- **Use Docker** for consistent rendering across developer machines and CI:

```bash
npx backstop test --docker
```

[^1][^2]

## 6. Typical workflow summary

| Step                        | Command                   | When to run                                   |
| --------------------------- | ------------------------- | --------------------------------------------- |
| Initialize                  | `npx backstop init`       | Once per project                              |
| Set baseline                | `npx backstop reference`  | After initial config or when adding new pages |
| Check for regressions       | `npx backstop test`       | After every UI change, in PR/CI               |
| Approve intentional changes | `npx backstop approve`    | When the diff is correct                      |
| Review report               | `npx backstop openReport` | To inspect the latest comparison              |

## 7. Optional: programmatic integration

If you want to run BackstopJS from a Node script or custom CLI, import it programmatically:

```javascript
const backstop = require('backstopjs');

backstop('test', { config: require('./backstop.json') })
  .then(() => process.exit(0))
  .catch(() => process.exit(1));
```

This is useful for building custom test runners or integrating into larger build pipelines [^3].

By combining committed reference images, CI-gated `backstop test`, and careful handling of dynamic content, you can reliably detect unintended visual changes on customer-facing pages before they reach production.

**References**

[^1]: [garris/BackstopJS GitHub Repo](https://github.com/garris/BackstopJS) (61%)

[^2]: [Testing Your Website for Visual Regressions With BackstopJS | Codurance](https://www.codurance.com/publications/2020/01/16/backstopjs-tutorial) (21%)

[^3]: [Programmatic Usage | garris/BackstopJS | DeepWiki](https://deepwiki.com/garris/BackstopJS/2.2-programmatic-usage) (18%)
