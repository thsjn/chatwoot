import { setActivePinia, createPinia } from 'pinia';
import { mount } from '@vue/test-utils';

import { useCrmBoardStore } from 'dashboard/store/crm/board';
import BoardColumn from '../BoardColumn.vue';

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

// The real vuedraggable drives Sortable against a live DOM, which has nothing to
// do with what the column renders: the double keeps the item slot and exposes
// the props the column drives it with.
vi.mock('vuedraggable', () => ({
  default: {
    name: 'Draggable',
    props: {
      modelValue: { type: Array, default: () => [] },
      disabled: { type: Boolean, default: false },
    },
    template: `
      <div data-testid="draggable" :data-disabled="String(disabled)">
        <div v-for="element in modelValue" :key="element.id">
          <slot name="item" :element="element" />
        </div>
      </div>
    `,
  },
}));

const buildDeal = (id, overrides = {}) => ({
  id,
  title: `Deal ${id}`,
  value_cents: 100000,
  currency: 'BRL',
  status: 'open',
  position: id * 1000,
  stage_entered_at: Math.floor(Date.now() / 1000),
  next_activity_at: Math.floor(Date.now() / 1000) + 86400,
  contact: { name: `Contact ${id}` },
  ...overrides,
});

const buildStage = (overrides = {}) => ({
  id: 10,
  name: 'Qualification',
  color: 'blue',
  category: 'open',
  deals_count: 2,
  deals_value_cents: 200000,
  rotting_days: null,
  wip_limit: null,
  ...overrides,
});

const mountColumn = (stage = buildStage()) =>
  mount(BoardColumn, { props: { stage } });

const dragDisabled = wrapper =>
  wrapper.get('[data-testid="draggable"]').attributes('data-disabled');

describe('BoardColumn.vue', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useCrmBoardStore();
    store.stages = [buildStage()];
    store.deals = { 10: [buildDeal(1), buildDeal(2)] };
    store.dealsMeta = { 10: { count: 2, currentPage: 1, isFetching: false } };
  });

  it('renders the stage name, its card count and its total', () => {
    const wrapper = mountColumn();

    expect(wrapper.text()).toContain('Qualification');
    expect(wrapper.get('[title="Total in this stage"]').text()).toBe('2');
    expect(wrapper.text()).toContain('2,000');
    expect(wrapper.findAllComponents({ name: 'DealCard' })).toHaveLength(2);
  });

  it('measures the column limit against the stage total', () => {
    // Only two cards are loaded, but the stage already holds twelve: the alert
    // has to light up before anyone presses "load more".
    const wrapper = mountColumn(buildStage({ deals_count: 12, wip_limit: 10 }));

    expect(wrapper.text()).toContain('12 of 10');
    expect(wrapper.text()).toContain('Column limit reached');
  });

  it('keeps the column limit quiet while the stage is under it', () => {
    const wrapper = mountColumn(buildStage({ deals_count: 4, wip_limit: 10 }));

    expect(wrapper.text()).toContain('4 of 10');
    expect(wrapper.text()).not.toContain('Column limit reached');
  });

  it('hides the filtered badge on an unfiltered board', () => {
    const wrapper = mountColumn();

    expect(wrapper.text()).not.toContain('Filtered:');
  });

  it('shows the filtered totals only when the backend sends them', () => {
    const wrapper = mountColumn(
      buildStage({
        filtered_deals_count: 1,
        filtered_deals_value_cents: 100000,
      })
    );

    expect(wrapper.text()).toContain('Filtered: 1');
    expect(wrapper.text()).toContain('1,000');
    expect(wrapper.text()).toContain('2,000');
  });

  it('offers no load more button when every card is on screen', () => {
    const wrapper = mountColumn();

    expect(wrapper.text()).not.toContain('Load more');
  });

  it('loads the next page when the column holds fewer cards than the stage', async () => {
    store.dealsMeta[10].count = 5;
    const loadMoreDeals = vi
      .spyOn(store, 'loadMoreDeals')
      .mockResolvedValue(null);
    const wrapper = mountColumn();

    const loadMore = wrapper
      .findAll('button')
      .find(button => button.text() === 'Load more');
    expect(loadMore).toBeTruthy();

    await loadMore.trigger('click');

    expect(loadMoreDeals).toHaveBeenCalledWith(10);
  });

  it('emits addDeal with the stage the plus button belongs to', async () => {
    const wrapper = mountColumn();

    await wrapper.get('[aria-label="Add deal"]').trigger('click');

    expect(wrapper.emitted('addDeal')).toStrictEqual([[10]]);
  });

  it('emits selectDeal with the card that was clicked', async () => {
    const wrapper = mountColumn();

    await wrapper.findAllComponents({ name: 'DealCard' })[1].trigger('click');

    expect(wrapper.emitted('selectDeal')).toStrictEqual([[2]]);
  });

  it('says the column is empty when it holds no cards', () => {
    store.deals = { 10: [] };
    const wrapper = mountColumn();

    expect(wrapper.text()).toContain('No deals in this stage');
  });

  it('drops the aggregates, the add button and the drag when archived', () => {
    store.showArchived = true;
    const wrapper = mountColumn(buildStage({ wip_limit: 10 }));

    expect(wrapper.find('[aria-label="Add deal"]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('2,000');
    expect(dragDisabled(wrapper)).toBe('true');
  });

  it('keeps the drag enabled on the live board', () => {
    expect(dragDisabled(mountColumn())).toBe('false');
  });
});
