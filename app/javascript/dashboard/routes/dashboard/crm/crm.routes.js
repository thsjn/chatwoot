import { frontendURL } from '../../../helper/URLHelper';
import CrmBoardIndex from './Index.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/crm'),
    component: CrmBoardIndex,
    name: 'crm_board',
    meta: {
      permissions: ['administrator', 'agent', 'custom_role'],
    },
  },
];
