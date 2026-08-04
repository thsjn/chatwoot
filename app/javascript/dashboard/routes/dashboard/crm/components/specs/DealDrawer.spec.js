import { setActivePinia, createPinia } from 'pinia';
import { mount, flushPromises } from '@vue/test-utils';

import { useCrmBoardStore } from 'dashboard/store/crm/board';
import CrmActivitiesAPI from 'dashboard/api/crm/activities';
import DealDrawer from '../DealDrawer.vue';

vi.mock('dashboard/api/crm/deals', () => ({
  default: { get: vi.fn(), move: vi.fn(), update: vi.fn(), delete: vi.fn() },
}));
vi.mock('dashboard/api/crm/pipelines', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/stages', () => ({
  default: { getStages: vi.fn() },
}));
vi.mock('dashboard/api/crm/lostReasons', () => ({
  default: { get: vi.fn() },
}));
vi.mock('dashboard/api/crm/sources', () => ({ default: { get: vi.fn() } }));

vi.mock('dashboard/api/crm/activities', () => ({
  default: {
    getActivities: vi.fn(),
    createActivity: vi.fn(),
    updateActivity: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

// The drawer only reads the agent/team/attribute lists, so the getters answer a
// plain box instead of a full vuex store.
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: () => ({ value: [] }),
  useStoreGetters: () => ({}),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 } }),
}));

const buildDeal = (overrides = {}) => ({
  id: 1,
  title: 'Fazenda Boa Vista',
  value_cents: 250000,
  currency: 'BRL',
  status: 'open',
  stage_id: 10,
  position: 1000,
  lock_version: 1,
  created_at: 1700000000,
  archived_at: null,
  next_activity_at: 1800000000,
  expected_close_on: '2026-03-14',
  contact: { name: 'Maria Silva', phone_number: '+5511999999999' },
  owner: null,
  team: null,
  source: null,
  conversations: [
    { id: 7, display_id: 42, is_origin: true, inbox: { name: 'WhatsApp' } },
    { id: 8, display_id: 43, is_origin: false, inbox: { name: 'Website' } },
  ],
  ...overrides,
});

const mountDrawer = () =>
  mount(DealDrawer, {
    props: { dealId: 1 },
    global: {
      stubs: { TeleportWithDirection: { template: '<div><slot /></div>' } },
      components: {
        RouterLink: { props: ['to'], template: '<a><slot /></a>' },
      },
    },
  });

const buttonWithText = (wrapper, text) =>
  wrapper.findAll('button').find(button => button.text().includes(text));

describe('DealDrawer.vue', () => {
  let store;

  const seed = (deal = buildDeal()) => {
    store.stages = [
      { id: 10, name: 'Qualification', category: 'open' },
      { id: 20, name: 'Lost', category: 'lost' },
    ];
    store.deals = { 10: [deal] };
    store.dealsMeta = { 10: { count: 1, currentPage: 1, isFetching: false } };
  };

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useCrmBoardStore();
    seed();
    CrmActivitiesAPI.getActivities.mockResolvedValue({
      data: { payload: [], meta: { count: 0, current_page: 1 } },
    });
  });

  it('renders the deal it was opened on', async () => {
    const wrapper = mountDrawer();
    await flushPromises();

    expect(wrapper.text()).toContain('Fazenda Boa Vista');
    expect(wrapper.text()).toContain('2,500');
    expect(wrapper.text()).toContain('Qualification');
    expect(wrapper.text()).toContain('Open');
    expect(wrapper.text()).toContain('Maria Silva');
  });

  it('warns when an open deal has no next activity scheduled', async () => {
    seed(buildDeal({ next_activity_at: null }));
    const wrapper = mountDrawer();
    await flushPromises();

    expect(wrapper.text()).toContain('No next activity scheduled');
    expect(wrapper.text()).toContain('Schedule a task so this deal keeps');
  });

  it('stays quiet when the deal already has a next activity', async () => {
    const wrapper = mountDrawer();
    await flushPromises();

    expect(wrapper.text()).not.toContain('No next activity scheduled');
  });

  it('lists the linked conversations and marks the one it came from', async () => {
    const wrapper = mountDrawer();
    await flushPromises();

    const links = wrapper.findAll('a');
    expect(links).toHaveLength(2);
    expect(links[0].text()).toContain('Conversation #42');
    expect(links[0].text()).toContain('WhatsApp');
    expect(links[1].text()).toContain('Conversation #43');
    expect(wrapper.text().match(/Origin/g)).toHaveLength(1);
  });

  it('says so when no conversation is linked', async () => {
    seed(buildDeal({ conversations: [] }));
    const wrapper = mountDrawer();
    await flushPromises();

    expect(wrapper.text()).toContain('No conversations linked to this deal');
  });

  it('leaves stage, status and lost reason read only', async () => {
    seed(
      buildDeal({
        status: 'lost',
        stage_id: 20,
        lost_reason: { id: 55, name: 'Price too high' },
      })
    );
    const wrapper = mountDrawer();
    await flushPromises();

    // The update endpoint refuses these three: they only change through a move,
    // so the drawer prints them instead of offering a control.
    const optionLabels = wrapper.findAll('option').map(option => option.text());
    expect(optionLabels).not.toContain('Lost');
    expect(optionLabels).not.toContain('Qualification');
    expect(optionLabels).not.toContain('Price too high');
    expect(wrapper.text()).toContain('Lost');
  });

  it('shows the lost reason on a lost deal', async () => {
    seed(
      buildDeal({
        status: 'lost',
        stage_id: 20,
        lost_reason: { id: 55, name: 'Price too high' },
      })
    );
    const wrapper = mountDrawer();
    await flushPromises();

    expect(wrapper.text()).toContain('Lost reason');
    expect(wrapper.text()).toContain('Price too high');
  });

  it('says nothing about a lost reason on an open deal', async () => {
    const wrapper = mountDrawer();
    await flushPromises();

    expect(wrapper.text()).not.toContain('Lost reason');
  });

  it('archives the deal only after the confirmation step', async () => {
    const archiveDeal = vi.spyOn(store, 'archiveDeal').mockResolvedValue();
    const wrapper = mountDrawer();
    await flushPromises();

    await buttonWithText(wrapper, 'Archive').trigger('click');

    expect(archiveDeal).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('Confirm archive');

    await buttonWithText(wrapper, 'Confirm archive').trigger('click');
    await flushPromises();

    expect(archiveDeal).toHaveBeenCalledWith(1);
    expect(wrapper.emitted('close')).toBeTruthy();
  });

  it('restores an archived deal without asking twice', async () => {
    seed(buildDeal({ archived_at: 1700000500 }));
    const unarchiveDeal = vi.spyOn(store, 'unarchiveDeal').mockResolvedValue();
    const wrapper = mountDrawer();
    await flushPromises();

    expect(wrapper.text()).toContain('Archived');
    expect(wrapper.findComponent({ name: 'ConfirmButton' }).exists()).toBe(
      false
    );

    await buttonWithText(wrapper, 'Restore').trigger('click');
    await flushPromises();

    expect(unarchiveDeal).toHaveBeenCalledWith(1);
    expect(wrapper.emitted('close')).toBeTruthy();
  });

  it('closes on the close button', async () => {
    const wrapper = mountDrawer();
    await flushPromises();

    await wrapper.get('[aria-label="Close deal panel"]').trigger('click');

    expect(wrapper.emitted('close')).toBeTruthy();
  });

  it('loads the timeline of the deal it was opened on', async () => {
    mountDrawer();
    await flushPromises();

    expect(CrmActivitiesAPI.getActivities).toHaveBeenCalledWith(1, {
      page: 1,
    });
  });
});