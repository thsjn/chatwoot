import store from 'dashboard/store';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { defaultRedirectPage } from 'dashboard/helper/routeHelpers';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper';

/**
 * The CRM module is opt-in per account through `settings.crm_kanban`, the same toggle the backend
 * checks in `Crm::ModuleEnabled`. The UI gate is a convenience — every endpoint answers 404 on its
 * own — but without it the board would mount and paint an empty funnel out of 404s.
 */

/**
 * The account record only lands in the store after `accounts/get`, which App.vue fires on mount —
 * i.e. AFTER the router guards on a cold page load. Without waiting for it a direct hit on
 * `/accounts/:id/crm` would always read `undefined` and bounce.
 *
 * @param {Number} accountId
 * @returns {Promise<Object>} The account record held by the store.
 */
const loadAccount = async accountId => {
  const getAccount = () => store.getters['accounts/getAccount'](accountId);

  if (!getAccount()?.id) {
    await store.dispatch('accounts/get');
  }

  return getAccount();
};

/**
 * @param {Number} accountId
 * @returns {Promise<Boolean>} Whether the CRM module is enabled for the account.
 */
export const isCrmModuleEnabled = async accountId => {
  const account = await loadAccount(accountId);
  return Boolean(account?.settings?.crm_kanban);
};

/**
 * Route guard for every CRM route. With the module off the user is sent to the same place Chatwoot
 * sends anyone reaching a route they may not open (`defaultRedirectPage`).
 *
 * @param {Object} to - Target route.
 * @returns {Promise<Boolean|String>} `true` to proceed, or the URL to redirect to.
 */
export const crmModuleGuard = async to => {
  const accountId = Number(to.params.accountId);

  if (await isCrmModuleEnabled(accountId)) return true;

  const permissions = getUserPermissions(
    store.getters.getCurrentUser,
    accountId
  );
  return frontendURL(defaultRedirectPage(to, permissions));
};
