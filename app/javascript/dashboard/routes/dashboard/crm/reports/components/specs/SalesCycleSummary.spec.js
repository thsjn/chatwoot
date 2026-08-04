import { setActivePinia, createPinia } from 'pinia';
import { mount } from '@vue/test-utils';

import SalesCycleSummary from '../SalesCycleSummary.vue';

vi.mock('dashboard/api/crm/reports', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/pipelines', () => ({ default: { get: vi.fn() } }));

const SECONDS_IN_A_DAY = 86400;

const mountSummary = salesCycle =>
  mount(SalesCycleSummary, { props: { salesCycle } });

// The four cards print the same kind of value, so reading them in order is what
// separates "time to win" from "time to lose".
const values = wrapper =>
  wrapper.findAll('[data-test-id="reportMetricValue"]').map(el => el.text());

describe('SalesCycleSummary.vue', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  it('reports the time to win apart from the time to lose', () => {
    const wrapper = mountSummary({
      won: { avg_cycle_seconds: 12 * SECONDS_IN_A_DAY, deals_count: 18 },
      lost: { avg_cycle_seconds: 30 * SECONDS_IN_A_DAY, deals_count: 25 },
    });

    expect(wrapper.text()).toContain('Time to win');
    expect(wrapper.text()).toContain('Deals won');
    expect(wrapper.text()).toContain('Time to lose');
    expect(wrapper.text()).toContain('Deals lost');
    expect(values(wrapper)).toStrictEqual(['12 d', '18', '30 d', '25']);
  });

  it('reads a short cycle in hours instead of a fraction of a day', () => {
    const wrapper = mountSummary({
      won: { avg_cycle_seconds: 9000, deals_count: 2 },
      lost: { avg_cycle_seconds: 90, deals_count: 1 },
    });

    expect(values(wrapper)).toStrictEqual(['2.5 h', '2', '1.5 min', '1']);
  });

  // No deal closed in the period means there is no average to report, and a
  // zero would read as "it takes no time at all".
  it('says there is no data instead of printing a zero cycle', () => {
    const wrapper = mountSummary({
      won: { avg_cycle_seconds: null, deals_count: 0 },
      lost: { avg_cycle_seconds: null, deals_count: 0 },
    });

    expect(values(wrapper)).toStrictEqual(['No data', '0', 'No data', '0']);
  });

  // Only one side of the pair having closed is the normal case early on, and it
  // must not blank out the side that does have an answer.
  it('reports the side that has an answer when only one has closed', () => {
    const wrapper = mountSummary({
      won: { avg_cycle_seconds: null, deals_count: 0 },
      lost: { avg_cycle_seconds: 4 * SECONDS_IN_A_DAY, deals_count: 3 },
    });

    expect(values(wrapper)).toStrictEqual(['No data', '0', '4 d', '3']);
  });

  it('survives a payload that carries neither side yet', () => {
    const wrapper = mountSummary({});

    expect(values(wrapper)).toStrictEqual(['No data', '0', 'No data', '0']);
  });
});
