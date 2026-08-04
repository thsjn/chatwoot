import { setActivePinia, createPinia } from 'pinia';
import { mount } from '@vue/test-utils';

import LossReasonsReport from '../LossReasonsReport.vue';

vi.mock('dashboard/api/crm/reports', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/pipelines', () => ({ default: { get: vi.fn() } }));

const ROWS = [
  {
    lost_reason: { id: 55, name: 'Price too high' },
    deals_count: 12,
    value_cents: 1800000,
  },
  {
    lost_reason: { id: 56, name: 'Bought from a competitor' },
    deals_count: 4,
    value_cents: 620000,
  },
];

// Deals marked as lost without recording a reason come back under a null
// reason: they are the ones a manager wants to see first.
const NO_REASON_ROW = {
  lost_reason: null,
  deals_count: 9,
  value_cents: 1100000,
};

const mountReport = (rows = ROWS) =>
  mount(LossReasonsReport, {
    props: { rows },
    // Chart.js draws on a canvas jsdom does not implement, and the numbers it
    // gets are the same ones the table below prints.
    global: { stubs: { BarChart: true } },
  });

describe('LossReasonsReport.vue', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  it('renders a row per reason with its count and value', () => {
    const wrapper = mountReport();
    const rows = wrapper.findAll('tbody tr');

    expect(rows).toHaveLength(2);
    expect(rows[0].text()).toContain('Price too high');
    expect(rows[0].text()).toContain('12');
    expect(rows[0].text()).toContain('18,000');
    expect(rows[1].text()).toContain('Bought from a competitor');
    expect(rows[1].text()).toContain('6,200');
  });

  it('names the deals that were lost without a reason recorded', () => {
    const wrapper = mountReport([...ROWS, NO_REASON_ROW]);
    const rows = wrapper.findAll('tbody tr');

    expect(rows).toHaveLength(3);
    expect(rows[2].text()).toContain('No reason recorded');
    expect(rows[2].text()).toContain('11,000');
  });

  it('names the columns it is breaking down', () => {
    const wrapper = mountReport();

    expect(wrapper.text()).toContain('Reason');
    expect(wrapper.text()).toContain('Deals');
    expect(wrapper.text()).toContain('Value');
  });

  it('feeds the chart the value lost per reason', () => {
    const wrapper = mountReport([...ROWS, NO_REASON_ROW]);
    const collection = wrapper
      .findComponent({ name: 'BarChart' })
      .props('collection');

    expect(collection.labels).toStrictEqual([
      'Price too high',
      'Bought from a competitor',
      'No reason recorded',
    ]);
    expect(collection.datasets[0].data).toStrictEqual([
      1800000, 620000, 1100000,
    ]);
  });

  // A reason nobody picked in the period simply does not come back, so a row
  // that IS here always carries a number worth reading.
  it('renders an empty table when no deal was lost in the period', () => {
    const wrapper = mountReport([]);

    expect(wrapper.findAll('tbody tr')).toHaveLength(0);
    expect(wrapper.text()).toContain('Reason');
  });
});
