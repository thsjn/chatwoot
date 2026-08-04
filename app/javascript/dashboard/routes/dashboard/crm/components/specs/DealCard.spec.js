import { mount } from '@vue/test-utils';
import DealCard from '../DealCard.vue';

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
