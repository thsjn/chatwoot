import { setActivePinia, createPinia } from 'pinia';
import { mount } from '@vue/test-utils';

import SourcesReport from '../SourcesReport.vue';

vi.mock('dashboard/api/crm/reports', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/pipelines', () => ({ default: { get: vi.fn() } }));

const ROWS = [
  {
    source: { id: 3, name: 'Website form', kind: 'landing' },
    won_count: 8,
    won_value_cents: 1250000,
    lost_count: 2,
    lost_value_cents: 300000,
    win_rate: 80,
  },
  {
    source: { id: 4, name: 'WhatsApp', kind: 'inbox' },
    won_count: 1,
    won_value_cents: 90000,
    lost_count: 3,
    lost_value_cents: 450000,
    win_rate: 25,
  },
];

// A deal closed without a channel tagged comes back under a null source. That
// hole is the whole reason the report exists, so it is a row like any other.
const NO_SOURCE_ROW = {
  source: null,
  won_count: 0,
  won_value_cents: 0,
  lost_count: 5,
  lost_value_cents: 720000,
  win_rate: 0,
};

const mountReport = (rows = ROWS) =>
  mount(SourcesReport, {
    props: { rows },
    // Chart.js draws on a canvas jsdom does not implement, and the numbers it
    // gets are the same ones the table below prints.
    global: { stubs: { BarChart: true } },
  });

describe('SourcesReport.vue', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  it('renders a row per channel with its wins, losses and win rate', () => {
    const wrapper = mountReport();
    const rows = wrapper.findAll('tbody tr');

    expect(rows).toHaveLength(2);
    expect(rows[0].text()).toContain('Website form');
    expect(rows[0].text()).toContain('12,500');
    expect(rows[0].text()).toContain('3,000');
    expect(rows[0].text()).toContain('80%');
    expect(rows[1].text()).toContain('WhatsApp');
    expect(rows[1].text()).toContain('25%');
  });

  it('formats the values as money in the currency of the report', () => {
    const wrapper = mountReport();

    expect(wrapper.text()).toContain('R$');
  });

  it('names the channel a deal came from with no source tagged', () => {
    const wrapper = mountReport([NO_SOURCE_ROW]);
    const rows = wrapper.findAll('tbody tr');

    expect(rows).toHaveLength(1);
    expect(rows[0].text()).toContain('No channel tagged');
    expect(rows[0].text()).toContain('7,200');
  });

  it('keeps the untagged row alongside the tagged ones', () => {
    const wrapper = mountReport([...ROWS, NO_SOURCE_ROW]);

    expect(wrapper.findAll('tbody tr')).toHaveLength(3);
    expect(wrapper.text()).toContain('No channel tagged');
  });

  it('labels both series on the legend and the table header', () => {
    const wrapper = mountReport();

    expect(wrapper.text()).toContain('Channel');
    expect(wrapper.text()).toContain('Won value');
    expect(wrapper.text()).toContain('Lost value');
    expect(wrapper.text()).toContain('Win rate');
  });

  it('feeds the chart the won and lost series of every channel', () => {
    const wrapper = mountReport([...ROWS, NO_SOURCE_ROW]);
    const collection = wrapper
      .findComponent({ name: 'BarChart' })
      .props('collection');

    expect(collection.labels).toStrictEqual([
      'Website form',
      'WhatsApp',
      'No channel tagged',
    ]);
    expect(collection.datasets[0].data).toStrictEqual([1250000, 90000, 0]);
    expect(collection.datasets[1].data).toStrictEqual([300000, 450000, 720000]);
  });

  it('renders an empty table when nothing was closed in the period', () => {
    const wrapper = mountReport([]);

    expect(wrapper.findAll('tbody tr')).toHaveLength(0);
    expect(wrapper.text()).toContain('Channel');
  });
});
