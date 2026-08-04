import { setActivePinia, createPinia } from 'pinia';
import { mount } from '@vue/test-utils';

import ForecastReport from '../ForecastReport.vue';

vi.mock('dashboard/api/crm/reports', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/pipelines', () => ({ default: { get: vi.fn() } }));

const ROWS = [
  {
    period: '2026-03-01',
    deals_count: 4,
    value_cents: 1000000,
    weighted_value_cents: 400000,
  },
  {
    period: '2026-04-01',
    deals_count: 2,
    value_cents: 500000,
    weighted_value_cents: 125000,
  },
];

// `period` is null for the open deals that still have no expected close date:
// real money the forecast cannot place on a month yet.
const NO_DATE_ROW = {
  period: null,
  deals_count: 3,
  value_cents: 900000,
  weighted_value_cents: 90000,
};

const mountReport = (rows = ROWS) =>
  mount(ForecastReport, {
    props: { rows },
    // Chart.js draws on a canvas jsdom does not implement, and the numbers it
    // gets are the same ones the table below prints.
    global: { stubs: { BarChart: true } },
  });

describe('ForecastReport.vue', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  it('renders a row per close month with its gross and weighted values', () => {
    const wrapper = mountReport();
    const rows = wrapper.findAll('tbody tr');

    expect(rows).toHaveLength(2);
    expect(rows[0].text()).toContain('Mar 2026');
    expect(rows[0].text()).toContain('10,000');
    expect(rows[0].text()).toContain('4,000');
    expect(rows[1].text()).toContain('Apr 2026');
    expect(rows[1].text()).toContain('1,250');
  });

  it('buckets the deals with no expected close date under their own label', () => {
    const wrapper = mountReport([NO_DATE_ROW]);
    const rows = wrapper.findAll('tbody tr');

    expect(rows).toHaveLength(1);
    expect(rows[0].text()).toContain('No close date');
    expect(rows[0].text()).toContain('9,000');
  });

  it('adds the undated bucket into the totals like any other row', () => {
    const wrapper = mountReport([...ROWS, NO_DATE_ROW]);
    const total = wrapper.get('tfoot tr');

    expect(total.text()).toContain('Total');
    // 4 + 2 + 3 deals, 24,000 gross and 6,150 weighted.
    expect(total.text()).toContain('9');
    expect(total.text()).toContain('24,000');
    expect(total.text()).toContain('6,150');
  });

  it('keeps the weighted value apart from the gross one', () => {
    const wrapper = mountReport();

    expect(wrapper.text()).toContain('Gross');
    expect(wrapper.text()).toContain('Weighted');
    expect(wrapper.text()).toContain('Close month');
  });

  it('feeds the chart the weighted and gross series of every bucket', () => {
    const wrapper = mountReport([...ROWS, NO_DATE_ROW]);
    const collection = wrapper
      .findComponent({ name: 'BarChart' })
      .props('collection');

    expect(collection.labels).toStrictEqual([
      'Mar 2026',
      'Apr 2026',
      'No close date',
    ]);
    expect(collection.datasets[0].data).toStrictEqual([400000, 125000, 90000]);
    expect(collection.datasets[1].data).toStrictEqual([
      1000000, 500000, 900000,
    ]);
  });

  it('totals to zero when there is nothing to forecast', () => {
    const wrapper = mountReport([]);

    expect(wrapper.findAll('tbody tr')).toHaveLength(0);
    expect(wrapper.get('tfoot tr').text()).toContain('Total');
  });
});
