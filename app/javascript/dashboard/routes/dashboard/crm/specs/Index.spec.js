import { setActivePinia, createPinia } from 'pinia';
import { mount, flushPromises } from '@vue/test-utils';
import { nextTick } from 'vue';

import { useCrmBoardStore } from 'dashboard/store/crm/board';
import CrmPipelinesAPI from 'dashboard/api/crm/pipelines';
import CrmDealsAPI from 'dashboard/api/crm/deals';
import CrmLostReasonsAPI from 'dashboard/api/crm/lostReasons';
import CrmSourcesAPI from 'dashboard/api/crm/sources';
import Index from '../Index.vue';

vi.mock('dashboard/api/crm/deals', () => ({
  default: { get: vi.fn(), move: vi.fn() },
}));
vi.mock('dashboard/api/crm/pipelines', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/stages', () => ({
  default: { getStages: vi.fn() },
}));
vi.mock('dashboard/api/crm/lostReasons', () => ({
  default: { get: vi.fn() },
}));
vi.mock('dashboard/api/crm/sources', () => ({ default: { get: vi.fn() } }));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: () => ({ value: [] }),
  useStoreGetters: () => ({ getCurrentRole: { value: 'administrator' } }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 } }),
  useRouter: () => ({ push: vi.fn() }),
}));

// Sortable needs a live DOM: the double only has to report whether the board
// handed it a frozen list.
vi.mock('vuedraggable', () => ({
  default: {
    name: 'Draggable',
    props: {
      modelValue: { type: Array, default: () => [] },
      disabled: { type: Boolean, default: false },
    },
    template:
      '<div data-testid="draggable" :data-disabled="String(disabled)" />',
  },
}));

const STAGE = {
  id: 10,
  name: 'Qualification',
  color: 'blue',
  category: 'open',
  deals_count: 0,
  deals_value_cents: 0,
  rotting_days: null,
  wip_limit: null,
};

const mountBoard = () =>
  mount(Index, {
    global: {
      stubs: {
        DealDrawer: true,
        DealFormModal: true,
        LostReasonModal: true,
      },
    },
  });

const buttonWithText = (wrapper, text) =>
  wrapper.findAll('button').find(button => button.text().includes(text));

const dragDisabled = wrapper =>
  wrapper.get('[data-testid="draggable"]').attributes('data-disabled');

describe('CRM board Index.vue', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useCrmBoardStore();
    CrmPipelinesAPI.get.mockResolvedValue({ data: { payload: [] } });
    CrmLostReasonsAPI.get.mockResolvedValue({ data: { payload: [] } });
    CrmSourcesAPI.get.mockResolvedValue({ data: { payload: [] } });
    CrmDealsAPI.get.mockResolvedValue({
      data: { payload: [], meta: { count: 0, current_page: 1 } },
    });
  });

  it('shows the empty state when the account has no pipeline yet', async () => {
    const wrapper = mountBoard();
    await flushPromises();

    expect(wrapper.text()).toContain('No deals to display');
    expect(CrmPipelinesAPI.get).toHaveBeenCalled();
  });

  it('holds the empty state back while the deals are still loading', async () => {
    const wrapper = mountBoard();
    await flushPromises();

    store.uiFlags.fetchingDeals = true;
    await nextTick();

    expect(wrapper.text()).not.toContain('No deals to display');
    expect(wrapper.findComponent({ name: 'Spinner' }).exists()).toBe(true);
  });

  it('renders a column per stage of the selected pipeline', async () => {
    const wrapper = mountBoard();
    await flushPromises();

    store.stages = [STAGE, { ...STAGE, id: 20, name: 'Negotiation' }];
    await nextTick();

    expect(wrapper.findAllComponents({ name: 'BoardColumn' })).toHaveLength(2);
    expect(wrapper.text()).toContain('Qualification');
    expect(wrapper.text()).toContain('Negotiation');
    expect(wrapper.text()).not.toContain('No deals to display');
  });

  it('raises the banner of a rejected move and lets it be dismissed', async () => {
    const wrapper = mountBoard();
    await flushPromises();

    store.moveError = {
      code: 'wip_limit_exceeded',
      messageKey: 'CRM.MOVE.WIP_EXCEEDED',
    };
    await nextTick();

    expect(wrapper.text()).toContain('Cannot move deal: column limit exceeded');

    await buttonWithText(wrapper, 'Dismiss').trigger('click');

    expect(store.moveError).toBeNull();
  });

  it('leaves the lost reason failures to their own dialog', async () => {
    const wrapper = mountBoard();
    await flushPromises();

    store.moveError = {
      code: 'lost_reason_required',
      messageKey: 'CRM.MOVE.LOST_REASON_REQUIRED',
    };
    await nextTick();

    expect(wrapper.text()).not.toContain('Lost reason is required');
    expect(wrapper.text()).not.toContain('Dismiss');
  });

  it('freezes the drag while the board lists the archived deals', async () => {
    const wrapper = mountBoard();
    await flushPromises();

    store.stages = [STAGE];
    await nextTick();

    expect(dragDisabled(wrapper)).toBe('false');

    await buttonWithText(wrapper, 'Archived').trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('Showing archived deals');
    expect(dragDisabled(wrapper)).toBe('true');
    expect(wrapper.find('[aria-label="Add deal"]').exists()).toBe(false);
  });
});