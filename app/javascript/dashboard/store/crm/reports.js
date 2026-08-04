import { defineStore } from 'pinia';
import {
  addDays,
  endOfDay,
  endOfMonth,
  getUnixTime,
  startOfDay,
  startOfMonth,
  startOfYear,
  subDays,
  subMonths,
} from 'date-fns';

import CrmReportsAPI from 'dashboard/api/crm/reports';
import CrmPipelinesAPI from 'dashboard/api/crm/pipelines';

// Every deal is created with `currency` defaulting to BRL, and the pipeline
// carries the currency new cards inherit in `settings.moeda_padrao`.
export const DEFAULT_CURRENCY = 'BRL';

/**
 * The window every metric is scoped by. Each service filters on the timestamp
 * that reads naturally for it (creation for the funnel, `closed_at` for what
 * was closed, `expected_close_on` for the forecast), so a period in the past
 * legitimately produces an empty forecast — hence `NEXT_90_DAYS`.
 */
export const DATE_RANGES = {
  LAST_7_DAYS: () => ({
    since: startOfDay(subDays(new Date(), 6)),
    until: endOfDay(new Date()),
  }),
  LAST_30_DAYS: () => ({
    since: startOfDay(subDays(new Date(), 29)),
    until: endOfDay(new Date()),
  }),
  LAST_90_DAYS: () => ({
    since: startOfDay(subDays(new Date(), 89)),
    until: endOfDay(new Date()),
  }),
  THIS_MONTH: () => ({
    since: startOfMonth(new Date()),
    until: endOfDay(new Date()),
  }),
  LAST_MONTH: () => ({
    since: startOfMonth(subMonths(new Date(), 1)),
    until: endOfMonth(subMonths(new Date(), 1)),
  }),
  THIS_YEAR: () => ({
    since: startOfYear(new Date()),
    until: endOfDay(new Date()),
  }),
  NEXT_90_DAYS: () => ({
    since: startOfDay(new Date()),
    until: endOfDay(addDays(new Date(), 90)),
  }),
};

export const DEFAULT_DATE_RANGE = 'LAST_30_DAYS';

const emptySalesCycle = () => ({
  won: { avg_cycle_seconds: null, deals_count: 0 },
  lost: { avg_cycle_seconds: null, deals_count: 0 },
});

export const useCrmReportsStore = defineStore('crmReports', {
  state: () => ({
    pipelines: [],
    selectedPipelineId: null,
    dateRangeKey: DEFAULT_DATE_RANGE,
    funnel: [],
    stageDurations: [],
    salesCycle: emptySalesCycle(),
    forecast: [],
    sources: [],
    lossReasons: [],
    uiFlags: {
      fetchingPipelines: false,
      fetchingFunnel: false,
      fetchingStageDurations: false,
      fetchingSalesCycle: false,
      fetchingForecast: false,
      fetchingSources: false,
      fetchingLossReasons: false,
      exporting: false,
    },
  }),

  getters: {
    getPipelines: state => state.pipelines,
    getSelectedPipeline: state =>
      state.pipelines.find(
        pipeline => pipeline.id === state.selectedPipelineId
      ) || null,
    getDateRangeKey: state => state.dateRangeKey,
    getFunnel: state => state.funnel,
    getStageDurations: state => state.stageDurations,
    getSalesCycle: state => state.salesCycle,
    getForecast: state => state.forecast,
    getSources: state => state.sources,
    getLossReasons: state => state.lossReasons,
    getUIFlags: state => state.uiFlags,

    isFetching: state => Object.values(state.uiFlags).some(Boolean),

    // `since`/`until` are what `DateRangeHelper` reads, and it only applies the
    // range when both are present.
    getDateRange: state => {
      const { since, until } = DATE_RANGES[state.dateRangeKey]();
      return { since: getUnixTime(since), until: getUnixTime(until) };
    },

    // The forecast buckets `expected_close_on`, so a window that already ended
    // can only ever answer "nothing to forecast" — the screen says so instead
    // of showing an empty chart as if the pipeline were empty.
    isRangeInThePast() {
      return this.getDateRange.until < getUnixTime(new Date());
    },

    getScopeParams() {
      return {
        ...(this.selectedPipelineId
          ? { pipeline_id: this.selectedPipelineId }
          : {}),
        ...this.getDateRange,
      };
    },

    /**
     * Currency of the numbers on screen. Every metric SUMS `value_cents` with
     * no conversion, so the only honest label is the currency the pipeline
     * hands to its cards — and it is only a label: a deal saved in another
     * currency still lands in the same sum at face value.
     */
    getCurrency() {
      return (
        this.getSelectedPipeline?.settings?.moeda_padrao || DEFAULT_CURRENCY
      );
    },

    /**
     * Currencies configured across the account's pipelines. More than one means
     * this account really does work in several currencies, and since the totals
     * are raw sums of cents the screen has to say the number cannot be trusted
     * as money.
     */
    getAccountCurrencies: state => [
      ...new Set(
        state.pipelines.map(
          pipeline => pipeline.settings?.moeda_padrao || DEFAULT_CURRENCY
        )
      ),
    ],

    hasMixedCurrencies() {
      return this.getAccountCurrencies.length > 1;
    },
  },

  actions: {
    async fetchPipelines() {
      this.uiFlags.fetchingPipelines = true;
      try {
        const { data } = await CrmPipelinesAPI.get();
        this.pipelines = data.payload;
        return this.pipelines;
      } finally {
        this.uiFlags.fetchingPipelines = false;
      }
    },

    async fetchFunnel() {
      this.uiFlags.fetchingFunnel = true;
      try {
        const { data } = await CrmReportsAPI.funnel(this.getScopeParams);
        this.funnel = data.payload;
      } finally {
        this.uiFlags.fetchingFunnel = false;
      }
    },

    async fetchStageDurations() {
      this.uiFlags.fetchingStageDurations = true;
      try {
        const { data } = await CrmReportsAPI.stageDurations(
          this.getScopeParams
        );
        this.stageDurations = data.payload;
      } finally {
        this.uiFlags.fetchingStageDurations = false;
      }
    },

    async fetchSalesCycle() {
      this.uiFlags.fetchingSalesCycle = true;
      try {
        const { data } = await CrmReportsAPI.salesCycle(this.getScopeParams);
        this.salesCycle = data.payload;
      } finally {
        this.uiFlags.fetchingSalesCycle = false;
      }
    },

    async fetchForecast() {
      this.uiFlags.fetchingForecast = true;
      try {
        const { data } = await CrmReportsAPI.forecast(this.getScopeParams);
        this.forecast = data.payload;
      } finally {
        this.uiFlags.fetchingForecast = false;
      }
    },

    async fetchSources() {
      this.uiFlags.fetchingSources = true;
      try {
        const { data } = await CrmReportsAPI.sources(this.getScopeParams);
        this.sources = data.payload;
      } finally {
        this.uiFlags.fetchingSources = false;
      }
    },

    async fetchLossReasons() {
      this.uiFlags.fetchingLossReasons = true;
      try {
        const { data } = await CrmReportsAPI.lossReasons(this.getScopeParams);
        this.lossReasons = data.payload;
      } finally {
        this.uiFlags.fetchingLossReasons = false;
      }
    },

    // The six metrics are independent requests on purpose: each block renders
    // as soon as its own answer lands instead of waiting for the slowest one.
    fetchAll() {
      return Promise.all([
        this.fetchFunnel(),
        this.fetchStageDurations(),
        this.fetchSalesCycle(),
        this.fetchForecast(),
        this.fetchSources(),
        this.fetchLossReasons(),
      ]);
    },

    async selectPipeline(pipelineId) {
      this.selectedPipelineId = Number(pipelineId);
      await this.fetchAll();
    },

    async setDateRange(dateRangeKey) {
      this.dateRangeKey = dateRangeKey;
      await this.fetchAll();
    },

    /**
     * The CSV is the one report that carries deal level rows — including the
     * per deal `currency`, which is where the exact money lives once the
     * aggregates had to give it up.
     *
     * @returns {Promise<string>} The raw CSV body.
     */
    async exportDeals() {
      this.uiFlags.exporting = true;
      try {
        const { data } = await CrmReportsAPI.dealsExport(this.getScopeParams);
        return data;
      } finally {
        this.uiFlags.exporting = false;
      }
    },
  },
});
