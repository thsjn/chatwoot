import { setActivePinia, createPinia } from 'pinia';
import { mount } from '@vue/test-utils';

import StageDurationsReport from '../StageDurationsReport.vue';

vi.mock('dashboard/api/crm/reports', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/pipelines', () => ({ default: { get: vi.fn() } }));

const SECONDS_IN_A_DAY = 86400;

// The endpoint answers a row per STAGE, even for the stages no card ever left,
// so a pipeline with no movement comes back full of rows carrying `null`.
const ROWS = [
  {
    stage_id: 10,
    name: 'Qualification',
    avg_duration_seconds: 2.4 * SECONDS_IN_A_DAY,
    transitions_count: 34,
  },
  {
    stage_id: 20,
    name: 'Negotiation',
    avg_duration_seconds: 5400,
    transitions_count: 7,
  },
  {
    stage_id: 30,
    name: 'Proposal',
    avg_duration_seconds: null,
    transitions_count: 0,
  },
];

const mountReport = (rows = ROWS) =>
  mount(StageDurationsReport, { props: { rows } });

describe('StageDurationsReport.vue', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  it('renders a row per stage with the average stay and the sample', () => {
    const wrapper = mountReport();
    const rows = wrapper.findAll('tbody tr');

    expect(rows).toHaveLength(3);
    expect(rows[0].text()).toContain('Qualification');
    expect(rows[0].text()).toContain('34');
    expect(rows[1].text()).toContain('Negotiation');
    expect(rows[1].text()).toContain('7');
  });

  it('reads the average in the largest unit that fits', () => {
    const wrapper = mountReport();
    const rows = wrapper.findAll('tbody tr');

    expect(rows[0].text()).toContain('2.4 d');
    expect(rows[1].text()).toContain('1.5 h');
  });

  // A stage nobody has left yet still gets its row, so the number of rows says
  // nothing about whether the report has anything to tell.
  it('keeps the row of a stage no card has left yet', () => {
    const wrapper = mountReport();
    const rows = wrapper.findAll('tbody tr');

    expect(rows[2].text()).toContain('Proposal');
    expect(rows[2].text()).toContain('No data');
    expect(rows[2].text()).toContain('0');
  });

  it('renders every stage even when none of them was ever completed', () => {
    const wrapper = mountReport(
      ROWS.map(row => ({
        ...row,
        avg_duration_seconds: null,
        transitions_count: 0,
      }))
    );

    expect(wrapper.findAll('tbody tr')).toHaveLength(3);
    expect(wrapper.text().match(/No data/g)).toHaveLength(3);
  });

  it('names the columns it is breaking down', () => {
    const wrapper = mountReport();

    expect(wrapper.text()).toContain('Stage');
    expect(wrapper.text()).toContain('Average time');
    expect(wrapper.text()).toContain('Moves');
  });
});
