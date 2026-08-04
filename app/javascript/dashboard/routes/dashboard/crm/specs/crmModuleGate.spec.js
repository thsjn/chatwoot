import { describe, it, expect, beforeEach, vi } from 'vitest';
import store from 'dashboard/store';
import { crmModuleGuard, isCrmModuleEnabled } from '../crmModuleGate';

vi.mock('dashboard/store', () => ({
  default: { getters: {}, dispatch: vi.fn() },
}));

describe('crmModuleGate', () => {
  const to = { name: 'crm_board', params: { accountId: '1' } };
  let account;

  beforeEach(() => {
    account = { id: 1, settings: {} };
    store.getters = {
      'accounts/getAccount': () => account,
      getCurrentUser: {
        id: 1,
        accounts: [
          { id: 1, role: 'administrator', permissions: ['administrator'] },
        ],
      },
    };
    store.dispatch = vi.fn();
  });

  it('lets the route through when the toggle is on', async () => {
    account.settings.crm_kanban = true;

    await expect(crmModuleGuard(to)).resolves.toBe(true);
  });

  it('redirects to the default page when the toggle is off', async () => {
    await expect(crmModuleGuard(to)).resolves.toBe('/app/accounts/1/dashboard');
  });

  it('redirects when the account carries no settings at all', async () => {
    account = { id: 1 };

    await expect(crmModuleGuard(to)).resolves.toBe('/app/accounts/1/dashboard');
  });

  // On a cold load the router runs before App.vue fetches the account, so the gate has to wait for
  // it instead of reading an empty record and bouncing the user off their own board.
  it('fetches the account when the store has not loaded it yet', async () => {
    account = {};
    store.dispatch = vi.fn(() => {
      account = { id: 1, settings: { crm_kanban: true } };
      return Promise.resolve();
    });

    await expect(isCrmModuleEnabled(1)).resolves.toBe(true);
    expect(store.dispatch).toHaveBeenCalledWith('accounts/get');
  });

  it('does not refetch an account already in the store', async () => {
    account.settings.crm_kanban = true;

    await isCrmModuleEnabled(1);

    expect(store.dispatch).not.toHaveBeenCalled();
  });
});
