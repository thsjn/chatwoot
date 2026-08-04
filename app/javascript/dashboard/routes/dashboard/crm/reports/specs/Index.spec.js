import { setActivePinia, createPinia } from 'pinia';
import { mount, flushPromises } from '@vue/test-utils';

import CrmReportsAPI from 'dashboard/api/crm/reports';
import CrmPipelinesAPI from 'dashboard/api/crm/pipelines';
import { useAlert } from 'dashboard/composables';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import Index from '../Index.vue';

vi.mock('dashboard/api/crm/reports', () => ({
  default: {
    funnel: vi.fn(),
    stageDurations: vi.fn(),
    salesCycle: vi.fn(),
    forecast: vi.fn(),
    sources: vi.fn(),
    lossReasons: vi.fn(),
    dealsExport: vi.fn(),
  },
}));
vi.mock('dashboard/api/crm/pipelines', () => ({ default: { get: vi.fn() } }));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

// The CSV download builds a Blob URL and clicks an anchor, which jsdom does not
// implement: what matters here is the file the page decided to hand over.
vi.mock('dashboard/helper/downloadHelper', () => ({
  downloadCsvFile: vi.fn(),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 } }),
  useRouter: () => ({ push: vi.fn() }),
}));

const pipeline = (overrides = {}) => ({
  id: 1,
  name: 'Sales',
  is_default: false,
  settings: { moeda_padrao: 'BRL' },
  ...overrides,
});

const FUNNEL_ROWS = [
  {
    stage_id: 10,
    name: 'Qualification',
    entered_count: 12,
    advanced_count: 5,
    conversion_rate: 41.6,
  },
];

const FORECAST_ROWS = [
  {
    period: '2026-05-01',
    deals_count: 3,
    value_cents: 900000,
    weighted_value_cents: 300000,
  },
];

// The page only orchestrates the blocks; each report has its own spec, and
// their charts need a canvas jsdom does not provide.
const mountReports = () =>
  mount(Index, {
    global: {
      stubs: {
        FunnelReport: true,
        SourcesReport: true,
        ForecastReport: true,
        LossReasonsReport: true,
        StageDurationsReport: true,
        SalesCycleSummary: true,
      },
    },
  });

const buttonWithText = (wrapper, text) =>
  wrapper.findAll('button').find(button => button.text().includes(text));

const lastCallParams = mock => mock.mock.calls[mock.mock.calls.length - 1][0];

describe('CRM reports Index.vue', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    CrmPipelinesAPI.get.mockResolvedValue({
      data: { payload: [pipeline({ id: 1 }), pipeline({ id: 2 })] },
    });
    CrmReportsAPI.funnel.mockResolvedValue({ data: { payload: FUNNEL_ROWS } });
    CrmReportsAPI.stageDurations.mockResolvedValue({
      data: {
        payload: [
          {
            stage_id: 10,
            name: 'Qualification',
            avg_duration_seconds: 3600,
            transitions_count: 4,
          },
        ],
      },
    });
    CrmReportsAPI.salesCycle.mockResolvedValue({
      data: {
        payload: {
          won: { avg_cycle_seconds: 86400, deals_count: 2 },
          lost: { avg_cycle_seconds: null, deals_count: 0 },
        },
      },
    });
    CrmReportsAPI.forecast.mockResolvedValue({
      data: { payload: FORECAST_ROWS },
    });
    CrmReportsAPI.sources.mockResolvedValue({ data: { payload: [] } });
    CrmReportsAPI.lossReasons.mockResolvedValue({ data: { payload: [] } });
    CrmReportsAPI.dealsExport.mockResolvedValue({
      data: 'id,title\n1,Fazenda Boa Vista\n',
    });
  });

  it('opens on the default pipeline and asks every metric for it', async () => {
    CrmPipelinesAPI.get.mockResolvedValue({
      data: {
        payload: [pipeline({ id: 1 }), pipeline({ id: 2, is_default: true })],
      },
    });
    mountReports();
    await flushPromises();

    expect(CrmReportsAPI.funnel).toHaveBeenCalledWith(
      expect.objectContaining({ pipeline_id: 2 })
    );
    expect(CrmReportsAPI.stageDurations).toHaveBeenCalled();
    expect(CrmReportsAPI.salesCycle).toHaveBeenCalled();
    expect(CrmReportsAPI.forecast).toHaveBeenCalled();
    expect(CrmReportsAPI.sources).toHaveBeenCalled();
    expect(CrmReportsAPI.lossReasons).toHaveBeenCalled();
  });

  it('falls back to the first pipeline when none is the default one', async () => {
    mountReports();
    await flushPromises();

    expect(CrmReportsAPI.funnel).toHaveBeenCalledWith(
      expect.objectContaining({ pipeline_id: 1 })
    );
  });

  it('asks the metrics again when another funnel is picked', async () => {
    const wrapper = mountReports();
    await flushPromises();

    await wrapper.findAll('select')[0].setValue('2');
    await flushPromises();

    expect(lastCallParams(CrmReportsAPI.funnel).pipeline_id).toBe(2);
    expect(lastCallParams(CrmReportsAPI.sources).pipeline_id).toBe(2);
  });

  it('asks the metrics again when the period changes', async () => {
    const wrapper = mountReports();
    await flushPromises();

    const thirtyDays = lastCallParams(CrmReportsAPI.funnel).since;

    await wrapper.findAll('select')[1].setValue('LAST_7_DAYS');
    await flushPromises();

    // A shorter window starts later, so the new request really did carry the
    // period the user picked.
    expect(lastCallParams(CrmReportsAPI.funnel).since).toBeGreaterThan(
      thirtyDays
    );
    expect(lastCallParams(CrmReportsAPI.forecast).since).toBeGreaterThan(
      thirtyDays
    );
  });

  it('exports the deals of the pipeline and the period on screen', async () => {
    const wrapper = mountReports();
    await flushPromises();

    await buttonWithText(wrapper, 'Export CSV').trigger('click');
    await flushPromises();

    expect(CrmReportsAPI.dealsExport).toHaveBeenCalledWith(
      expect.objectContaining({ pipeline_id: 1 })
    );
    expect(downloadCsvFile).toHaveBeenCalledWith(
      expect.stringMatching(/^crm-deals-\d{2}-\d{2}-\d{4}\.csv$/),
      'id,title\n1,Fazenda Boa Vista\n'
    );
  });

  it('says so when the export could not be produced', async () => {
    CrmReportsAPI.dealsExport.mockRejectedValue(new Error('boom'));
    const wrapper = mountReports();
    await flushPromises();

    await buttonWithText(wrapper, 'Export CSV').trigger('click');
    await flushPromises();

    expect(downloadCsvFile).not.toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith('Could not export the deals');
  });

  it('names the currency when every pipeline runs the same one', async () => {
    const wrapper = mountReports();
    await flushPromises();

    expect(wrapper.text()).toContain('Amounts are shown in BRL');
    expect(wrapper.text()).not.toContain('more than one currency');
  });

  it('warns that the totals mix currencies when the account runs more', async () => {
    CrmPipelinesAPI.get.mockResolvedValue({
      data: {
        payload: [
          pipeline({ id: 1 }),
          pipeline({ id: 2, settings: { moeda_padrao: 'USD' } }),
        ],
      },
    });
    const wrapper = mountReports();
    await flushPromises();

    expect(wrapper.text()).toContain('more than one currency (BRL, USD)');
    // Stamping a symbol on a sum of two currencies would be a lie, so the note
    // changes with it.
    expect(wrapper.text()).toContain('Amounts are shown without a currency');
    expect(wrapper.text()).not.toContain('Amounts are shown in BRL');
  });

  it('explains that a period already over cannot forecast anything', async () => {
    const wrapper = mountReports();
    await flushPromises();

    expect(wrapper.text()).not.toContain('The selected period has already');

    await wrapper.findAll('select')[1].setValue('LAST_MONTH');
    await flushPromises();

    expect(wrapper.text()).toContain(
      'The selected period has already ended, so it can only show deals'
    );
  });

  // The funnel and the time per stage answer a row PER STAGE even for stages no
  // deal ever touched, so an untouched pipeline comes back full of zeros and the
  // number of rows says nothing about whether there is anything to read.
  it('keeps the empty state on a pipeline nothing went through', async () => {
    CrmReportsAPI.funnel.mockResolvedValue({
      data: {
        payload: [
          { ...FUNNEL_ROWS[0], entered_count: 0, advanced_count: 0 },
          {
            stage_id: 20,
            name: 'Negotiation',
            entered_count: 0,
            advanced_count: 0,
            conversion_rate: 0,
          },
        ],
      },
    });
    CrmReportsAPI.stageDurations.mockResolvedValue({
      data: {
        payload: [
          {
            stage_id: 10,
            name: 'Qualification',
            avg_duration_seconds: null,
            transitions_count: 0,
          },
        ],
      },
    });
    const wrapper = mountReports();
    await flushPromises();

    expect(wrapper.text()).toContain(
      'No deals went through this pipeline in the selected period'
    );
    expect(wrapper.text()).toContain(
      'No stage was completed in the selected period'
    );
  });

  it('tells the account to create a funnel before reporting on it', async () => {
    CrmPipelinesAPI.get.mockResolvedValue({ data: { payload: [] } });
    const wrapper = mountReports();
    await flushPromises();

    expect(wrapper.text()).toContain(
      'Create a pipeline to see the funnel metrics'
    );
    expect(wrapper.text()).not.toContain('Conversion funnel');
    expect(CrmReportsAPI.funnel).not.toHaveBeenCalled();
  });
});
