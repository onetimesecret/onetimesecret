// e2e/support/workspaces.ts
//
// A throwaway account that owns two workspaces (organizations), for the
// e2e/full/ suites that drive the workspace switcher.
//
// The switcher is hidden for the storageState account: it owns only its
// default workspace and is its only member (the solo rule in
// src/shared/composables/useScopeSwitcherVisibility.ts), and the suites that
// assert that must keep it so. Owning a second workspace is enough to show
// the switcher, so this module signs up a new account and gives it one
// through the organizations API. It needs ENABLE_ORGS=true on the target
// (the full lane in .github/workflows/e2e.yml sets it).
//
// The owner is created once per worker process and shared by every test in
// that worker; a retry runs in a fresh worker and gets a fresh owner. Each
// test gets its own browser context signed in as the owner (`ownerPage`).
// Tests share the owner's server session, so they must not assume which
// workspace is current when a page loads.

import {
  expect,
  test as base,
  type Browser,
  type BrowserContext,
  type Page,
} from '@playwright/test';

import {
  closeContexts,
  createOrganization,
  signUpAndSignIn,
  type CreatedOrganization,
} from './members';
import { getFirstOrganization } from './organizations';

type StorageState = Awaited<ReturnType<BrowserContext['storageState']>>;

export interface WorkspaceOwner {
  storageState: StorageState;
  /** The workspace created with the account (is_default). */
  defaultWorkspace: CreatedOrganization;
  /** A second workspace created through the organizations API. */
  secondWorkspace: CreatedOrganization;
  /** Path of the receipt page of a secret the owner created. */
  receiptPath: string;
}

let workspaceOwner: WorkspaceOwner | undefined;

async function createWorkspaceOwner(browser: Browser): Promise<WorkspaceOwner> {
  const opened: BrowserContext[] = [];
  try {
    const owner = await signUpAndSignIn(browser, opened, 'workspace-owner');
    const { page } = owner;

    const first = await getFirstOrganization(page);
    const listResponse = await page.request.get('/api/organizations');
    expect(listResponse.ok(), 'GET /api/organizations').toBe(true);
    const { records } = (await listResponse.json()) as {
      records: { extid: string; objid: string; display_name: string; is_default: boolean }[];
    };
    const defaultRecord = records.find((org) => org.extid === first.extid);
    expect(defaultRecord?.is_default, 'a new account owns its default workspace').toBe(true);

    const secondWorkspace = await createOrganization(page, 'Second Workspace');

    await page.goto('/dashboard');
    await page.getByRole('textbox', { name: 'Secret content' }).fill('workspace owner receipt');
    await page.getByTestId('split-button-submit').click();
    await page.waitForURL(/\/receipt\/[^/]+$/);
    const receiptPath = new URL(page.url()).pathname;

    return {
      storageState: await owner.context.storageState(),
      defaultWorkspace: {
        extid: first.extid,
        objid: defaultRecord!.objid,
        name: defaultRecord!.display_name,
      },
      secondWorkspace,
      receiptPath,
    };
  } finally {
    await closeContexts(opened);
  }
}

/** `test` with the two-workspace owner (`owner`) and a page signed in as it (`ownerPage`). */
export const test = base.extend<{ owner: WorkspaceOwner; ownerPage: Page }>({
  owner: async ({ browser }, use) => {
    workspaceOwner ??= await createWorkspaceOwner(browser);
    await use(workspaceOwner);
  },
  ownerPage: async ({ browser, owner }, use) => {
    const context = await browser.newContext({ storageState: owner.storageState });
    const page = await context.newPage();
    page.setDefaultTimeout(15000);
    await use(page);
    await context.close();
  },
});

export { expect };

/** The owner's workspace that is not `workspace`. */
export function otherWorkspace(
  owner: WorkspaceOwner,
  workspace: CreatedOrganization
): CreatedOrganization {
  return workspace.extid === owner.defaultWorkspace.extid
    ? owner.secondWorkspace
    : owner.defaultWorkspace;
}
