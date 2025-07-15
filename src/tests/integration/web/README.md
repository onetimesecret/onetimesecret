# Playwright

Playwright is a powerful tool for browser automation and end-to-end testing. This README provides an overview of how to set up and run Playwright tests in the integration test suite.

## Getting Started

1. Install dependencies:

```bash
pnpm install
pnpm exec playwright install
```

2. Set up the environment:

Before running the tests, ensure you have the necessary environment variables configured. These typically include:

- `API_URL`: The URL of the Onetime Secret API (e.g., https://onetimesecret.com/api)
- `TEST_USER`: A test user account for running the integration tests

3. Running the tests:

To run the Playwright tests, use the following command:

```bash
pnpm run playwright
```

This will execute all integration tests, including those that interact with the Onetime Secret web interface.

4. Test structure:

Our Playwright tests are organized to cover key user flows, such as:
- Creating a new secret
- Retrieving a secret
- Verifying secret expiration

Each test file focuses on a specific feature or user journey, ensuring comprehensive coverage of Onetime Secret's core functionality.

5. Continuous Integration:

These tests are automatically run as part of our CI/CD pipeline to ensure the reliability and security of the Onetime Secret service with each update.

## Running Tests

Playwright tests for Onetime Secret can be run both locally in Visual Studio Code and as part of our continuous integration pipeline using GitHub Actions.

### Running Tests in Visual Studio Code

To run Playwright tests in VS Code:

1. Install the Playwright Test for VS Code extension.
2. Open the test file you want to run.
3. Click the "Run Test" or "Debug Test" CodeLens above each test.

Alternatively, you can use the Test Explorer to run or debug all tests:

1. Open the Testing view in VS Code's left sidebar.
2. Click the play button next to "Playwright Tests" to run all tests.
3. Use the debug icon to start a debugging session for your tests.

### GitHub Actions Workflow

We use GitHub Actions to automatically run our Playwright tests on push to main/master branches and on pull requests. Here's an overview of our workflow:

```yaml
name: Playwright Tests
on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]
jobs:
  test:
    timeout-minutes: 60
    runs-on: ubuntu-24.04
    steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-node@v4
      with:
        node-version: lts/*
    - name: Install dependencies
      run: npm install -g pnpm && pnpm install
    - name: Install Playwright Browsers
      run: pnpm exec playwright install --with-deps
    - name: Run Playwright tests
      run: pnpm exec playwright test
    - uses: actions/upload-artifact@v4
      if: ${{ !cancelled() }}
      with:
        name: playwright-report
        path: playwright-report/
        retention-days: 30
```

This workflow:
1. Triggers on pushes to main/master and on pull requests.
2. Sets up Node.js and installs dependencies using pnpm.
3. Installs Playwright browsers.
4. Runs all Playwright tests.
5. Uploads the test report as an artifact, which can be accessed for 30 days.

To view test results:
1. Go to the Actions tab in the GitHub repository.
2. Click on the relevant workflow run.
3. Download the playwright-report artifact to view detailed test results.

This setup ensures that our integration tests are run consistently across different environments and that any issues are caught early in the development process


## Writing Tests

When writing Playwright tests for Onetime Secret, there are several key techniques and APIs you should be familiar with. This section covers some of the most commonly used methods for interacting with and evaluating web pages.



### Interacting with page elements

Playwright provides a rich set of APIs for interacting with page elements. Here are some common operations:

```typescript
// Click an element
await page.click('button#submit');

// Fill in a form field
await page.fill('input#username', 'testuser');

// Select an option from a dropdown
await page.selectOption('select#country', 'USA');

// Check a checkbox
await page.check('input#terms');
```

### Handling navigation

When testing navigation in your app, you can use the following methods:

```typescript
// Navigate to a URL
await page.goto('https://onetimesecret.com');

// Wait for navigation to complete after an action
await Promise.all([
  page.waitForNavigation(),
  page.click('a.nav-link')
]);

// Go back or forward
await page.goBack();
await page.goForward();
```

### Working with iframes

If your app uses iframes, you can interact with them like this:

```typescript
// Get an iframe
const frame = page.frame('iframe-name');

// Interact with elements inside the iframe
await frame.click('button#submit-in-iframe');
```

### Managing browser contexts

Browser contexts allow you to create isolated browser sessions:

```typescript
const browser = await chromium.launch();
const context = await browser.newContext();
const page = await context.newPage();

// Use the page for testing...

await context.close();
await browser.close();
```

### Handling network requests

Playwright allows you to intercept and modify network requests:

```typescript
// Intercept requests
await page.route('**/*.{png,jpg,jpeg}', route => route.abort());

// Mock API responses
await page.route('**/api/data', route => {
  route.fulfill({
    status: 200,
    body: JSON.stringify({ key: 'mocked value' })
  });
});
```

### Evaluating page contents

  The page.evaluate() API can run a JavaScript function in the context of the web page and bring results back to the Playwright environment. Browser globals like window and document can be used in evaluate.

 ```typescript
   const href = await page.evaluate(() => document.location.href);

   // Or if the result is a promise
   const status = await page.evaluate(async () => {
     const response = await fetch(location.href);
     return response.status;
   });

   const data = 'some data';
   // Pass |data| as a parameter.
   const result = await page.evaluate(data => {
     window.myApp.use(data);
   }, data);
```


  Running initialization scripts:

  First, create a preload.js file that contains the mock.

```typescript
  // preload.js
  Math.random = () => 42;
 ```

  Next, add init script to the page.
```typescript
  import { test, expect } from '@playwright/test';
  import path from 'path';

  test.beforeEach(async ({ page }) => {
    // Add script for every test in the beforeEach hook.
    // Make sure to correctly resolve the script path.
    await page.addInitScript({ path: path.resolve(__dirname, '../mocks/preload.js') });
  });
 ```

  Alternatively, you can pass a function instead of creating a preload script file. This is more convenient for short or one-off scripts. You can also pass an argument this way.

```typescript
  import { test, expect } from '@playwright/test';

  // Add script for every test in the beforeEach hook.
  test.beforeEach(async ({ page }) => {
    const value = 42;
    await page.addInitScript(value => {
      Math.random = () => value;
    }, value);
  });
 ```
