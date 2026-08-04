import { setActivePinia, createPinia } from 'pinia';
import { mount } from '@vue/test-utils';

import { useCrmBoardStore } from 'dashboard/store/crm/board';
import DealCard from '../DealCard.vue';

vi.mock('dashboard/api/crm/deals', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/pipelines', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/stages', () => ({
  default: { getStages: vi.fn() },
}));
vi.mock('dashboard/api/crm/lostReasons', () => ({
  default: { get: vi.fn() },
}));
vi.mock('dashboard/api/crm/sources', () => ({ default: { get: vi.fn() } }));

const SECONDS_IN_A_DAY = 86400;
const nowInSeconds = () => Math.floor(Date.now() / 1000);

const buildDeal = (overrides = {}) => ({
  id: 1,
  title: 'Fazenda Boa Vista',
  value_cents: 250000,
  currency: 'BRL',
  status: 'open',
  next_activity_at: nowInSeconds() + SECONDS_IN_A_DAY,
  stage_entered_at: nowInSeconds(),
  expected_close_on: null,
  contact: { name: 'Maria Silva' },
  ...overrides,
});

const mountCard = (props = {}) =>
  mount(DealCard, { props: { deal: buildDeal(), ...props } });

// The badge only differs by colour between the two rotting levels, so the class
// is the single observable that separates "late" from "very late".
const rottingBadge = wrapper =>
  wrapper.findAll('span').find(node => node.text().startsWith('Inactive'));

describe('DealCard.vue', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  // Realtime pushes merge over the existing card and can omit `currency` (see
  // `applyRealtimeDeal` in the board store); `Intl.NumberFormat` throws on
  // `currency: undefined`, so the card must fall back instead of crashing.
  it('falls back to the pipeline currency when the deal has none', () => {
    const store = useCrmBoardStore();
    store.pipelines = [{ id: 1, settings: { moeda_padrao: 'USD' } }];
    store.selectedPipelineId = 1;

    const wrapper = mountCard({
      deal: buildDeal({ currency: undefined }),
    });

    expect(wrapper.text()).toContain('$');
  });

  it('falls back to BRL when neither the deal nor the pipeline carry a currency', () => {
    const wrapper = mountCard({
      deal: buildDeal({ currency: undefined }),
    });

    expect(wrapper.text()).toContain('R$');
  });

  it('renders the title, the formatted value and the contact', () => {
    const wrapper = mountCard();

    expect(wrapper.text()).toContain('Fazenda Boa Vista');
    expect(wrapper.text()).toContain('2,500');
    expect(wrapper.text()).toContain('Maria Silva');
  });

  it('keeps the card clean while it is inside the rotting window', () => {
    const wrapper = mountCard({
      deal: buildDeal({
        stage_entered_at: nowInSeconds() - 3 * SECONDS_IN_A_DAY,
      }),
      rottingDays: 5,
    });

    expect(wrapper.text()).not.toContain('Inactive for');
  });

  it('flags the card in amber once it passes the rotting window', () => {
    const wrapper = mountCard({
      deal: buildDeal({
        stage_entered_at: nowInSeconds() - 6 * SECONDS_IN_A_DAY,
      }),
      rottingDays: 5,
    });
    const badge = rottingBadge(wrapper);

    expect(badge.text()).toBe('Inactive for 6 days');
    expect(badge.classes()).toContain('bg-n-amber-3');
  });

  it('escalates the flag to red once the card doubles the window', () => {
    const wrapper = mountCard({
      deal: buildDeal({
        stage_entered_at: nowInSeconds() - 10 * SECONDS_IN_A_DAY,
      }),
      rottingDays: 5,
    });
    const badge = rottingBadge(wrapper);

    expect(badge.text()).toBe('Inactive for 10 days');
    expect(badge.classes()).toContain('bg-n-ruby-3');
  });

  it('never flags a card of a stage without a rotting window', () => {
    const wrapper = mountCard({
      deal: buildDeal({
        stage_entered_at: nowInSeconds() - 400 * SECONDS_IN_A_DAY,
      }),
    });

    expect(wrapper.text()).not.toContain('Inactive for');
  });

  it('warns about an open deal with no next activity scheduled', () => {
    const wrapper = mountCard({
      deal: buildDeal({ next_activity_at: null }),
    });

    expect(wrapper.text()).toContain('No next activity scheduled');
  });

  it('says nothing when the open deal has a next activity', () => {
    const wrapper = mountCard();

    expect(wrapper.text()).not.toContain('No next activity scheduled');
  });

  it('does not chase a closed deal for a next activity', () => {
    const wrapper = mountCard({
      deal: buildDeal({ status: 'won', next_activity_at: null }),
    });

    expect(wrapper.text()).not.toContain('No next activity scheduled');
  });

  it('renders the expected close date when the deal carries one', () => {
    const wrapper = mountCard({
      deal: buildDeal({ expected_close_on: '2026-03-14' }),
    });

    expect(wrapper.text()).toContain('Mar');
    expect(wrapper.text()).toContain('14');
  });

  it('renders the owner avatar only when the deal has an owner', () => {
    expect(mountCard().findComponent({ name: 'Avatar' }).exists()).toBe(false);

    const wrapper = mountCard({
      deal: buildDeal({ owner: { name: 'Ana', thumbnail: '' } }),
    });

    expect(wrapper.findComponent({ name: 'Avatar' }).exists()).toBe(true);
  });
});
