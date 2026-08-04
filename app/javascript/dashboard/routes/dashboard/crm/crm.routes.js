import { frontendURL } from '../../../helper/URLHelper';
import CrmBoardIndex from './Index.vue';
import CrmReportsIndex from './reports/Index.vue';
import CrmSettingsIndex from './settings/Index.vue';
import CrmSettingsPipelines from './settings/PipelinesIndex.vue';
import CrmSettingsStages from './settings/StagesIndex.vue';
import CrmSettingsSources from './settings/SourcesIndex.vue';
import CrmSettingsLostReasons from './settings/LostReasonsIndex.vue';

// The funnel configuration is administrator only on the backend (`Crm::PipelinePolicy`,
// `Crm::StagePolicy`, `Crm::SourcePolicy`, `Crm::LostReasonPolicy` all gate create/update/destroy
// on `administrator?`), so the routes carry the same restriction instead of letting an agent
// reach a screen whose every button answers 401.
const ADMIN_ONLY = { permissions: ['administrator'] };

export const routes = [
  {
    path: frontendURL('accounts/:accountId/crm'),
    component: CrmBoardIndex,
    name: 'crm_board',
    meta: {
      permissions: ['administrator', 'agent', 'custom_role'],
    },
  },
  {
    path: frontendURL('accounts/:accountId/crm/reports'),
    component: CrmReportsIndex,
    name: 'crm_reports',
    // `Crm::ReportPolicy` opens the metrics to agents too: an agent has to see
    // where their own deals stall, and a pipeline restricted by owner already
    // limits the aggregates to the deals they can see on the board.
    meta: {
      permissions: ['administrator', 'agent', 'custom_role'],
    },
  },
  {
    path: frontendURL('accounts/:accountId/crm/settings'),
    component: CrmSettingsIndex,
    meta: ADMIN_ONLY,
    children: [
      {
        path: '',
        redirect: to => ({
          name: 'crm_settings_pipelines',
          params: { accountId: to.params.accountId },
        }),
      },
      {
        path: 'pipelines',
        name: 'crm_settings_pipelines',
        component: CrmSettingsPipelines,
        meta: ADMIN_ONLY,
      },
      {
        path: 'stages',
        name: 'crm_settings_stages',
        component: CrmSettingsStages,
        meta: ADMIN_ONLY,
      },
      {
        path: 'sources',
        name: 'crm_settings_sources',
        component: CrmSettingsSources,
        meta: ADMIN_ONLY,
      },
      {
        path: 'lost-reasons',
        name: 'crm_settings_lost_reasons',
        component: CrmSettingsLostReasons,
        meta: ADMIN_ONLY,
      },
    ],
  },
];
