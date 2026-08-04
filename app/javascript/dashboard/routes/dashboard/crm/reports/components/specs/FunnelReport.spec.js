import { setActivePinia, createPinia } from 'pinia';
import { mount } from '@vue/test-utils';

import FunnelReport from '../FunnelReport.vue';

vi.mock('dashboard/api/crm/reports', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/pipelines', () => ({ default: { get: vi.fn() } }));

const ROWS = [
  {
    stage_id: 10,
    name: 'Qualification',
    entered_count: 120,
    advanced_count: 60,
    conversion_rate: 50,
  },
  {
    stage_id: 20,
    name: 'Negotiation',
    entered_count: 60,
    advanced_count: 9,
    conversion_rate: 15.25,
  },
];

const mountReport = (rows = ROWS) =>
  mount(FunnelReport, {
    props: { rows },
    // Chart.js draws on a canvas jsdom does not implement, and the numbers it
    // gets are the same ones the table below prints.
    global: { stubs: { BarChart: true } },
  });

describe('FunnelReport.vue', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  it('renders a row per stage with its counts and conversion', () => {
    const wrapper = mountReport();
    const rows = wrapper.findAll('tbody tr');

    expect(rows).toHaveLength(2);
    expect(rows[0].text()).toContain('Qualification');
    expect(rows[0].text()).toContain('120');
    expect(rows[0].text()).toContain('60');
    expect(rows[0].text()).toContain('50%');
    expect(rows[1].text()).toContain('15.3%');
  });

  it('labels both series on the legend and the table header', () => {
    const wrapper = mountReport();

    expect(wrapper.text()).toContain('Entered');
    expect(wrapper.text()).toContain('Advanced');
    expect(wrapper.text()).toContain('Conversion');
  });

  it('feeds the chart the entered and advanced series of every stage', () => {
    const wrapper = mountReport();
    const collection = wrapper
      .findComponent({ name: 'BarChart' })
      .props('collection');

    expect(collection.labels).toStrictEqual(['Qualification', 'Negotiation']);
    expect(collection.datasets[0].data).toStrictEqual([120, 60]);
    expect(collection.datasets[1].data).toStrictEqual([60, 9]);
  });

  it('renders an empty table when the period has no stage data', () => {
    const wrapper = mountReport([]);

    expect(wrapper.findAll('tbody tr')).toHaveLength(0);
    expect(wrapper.text()).toContain('Stage');
  });
});