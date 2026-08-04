<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { format } from 'date-fns';

import { useAlert } from 'dashboard/composables';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import { DATE_RANGES, useCrmReportsStore } from 'dashboard/store/crm/reports';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ReportBlock from './components/ReportBlock.vue';
import FunnelReport from './components/FunnelReport.vue';
import ForecastReport from './components/ForecastReport.vue';
import SourcesReport from './components/SourcesReport.vue';
import LossReasonsReport from './components/LossReasonsReport.vue';
import StageDurationsReport from './components/StageDurationsReport.vue';
import SalesCycleSummary from './components/SalesCycleSummary.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useCrmReportsStore();

const uiFlags = computed(() => store.getUIFlags);

const openBoard = () =>
  router.push({
    name: 'crm_board',
    params: { accountId: route.params.accountId },
  });

const selectedPipelineId = computed({
  get: () => store.getSelectedPipeline?.id ?? '',
  set: value => store.selectPipeline(value),
});

const dateRangeKey = computed({
  get: () => store.getDateRangeKey,
  set: value => store.setDateRange(value),
});

const pipelineOptions = computed(() =>
  store.getPipelines.map(pipeline => ({
    value: pipeline.id,
    label: pipeline.name,
  }))
);

const dateRangeOptions = computed(() =>
  Object.keys(DATE_RANGES).map(key => ({
    value: key,
    label: t(`CRM.REPORTS.DATE_RANGE.${key}`),
  }))
);

const salesCycle = computed(() => store.getSalesCycle);

// The funnel and the time per stage always answer one row PER STAGE, even for
// stages no deal ever touched, so a pipeline with no movement comes back full
// of zeros instead of empty. The emptiness has to be read from the numbers.
const hasFunnelData = computed(() =>
  store.getFunnel.some(row => row.entered_count > 0)
);

const hasStageDurations = computed(() =>
  store.getStageDurations.some(row => row.avg_duration_seconds !== null)
);

const hasSalesCycle = computed(
  () =>
    (salesCycle.value.won?.deals_count || 0) +
      (salesCycle.value.lost?.deals_count || 0) >
    0
);

const hasNoPipeline = computed(
  () => !uiFlags.value.fetchingPipelines && !store.getPipelines.length
);

const exportDeals = async () => {
  try {
    const csv = await store.exportDeals();
    downloadCsvFile(`crm-deals-${format(new Date(), 'dd-MM-yyyy')}.csv`, csv);
  } catch (error) {
    useAlert(t('CRM.REPORTS.EXPORT_ERROR'));
  }
};

onMounted(async () => {
  const pipelines = await store.fetchPipelines();
  const pipeline = pipelines.find(item => item.is_default) || pipelines[0];
  if (pipeline) await store.selectPipeline(pipeline.id);
});
</script>

<template>
  <main
    class="flex flex-col w-full h-full min-h-0 overflow-y-auto bg-n-background"
  >
    <header
      class="flex flex-wrap items-center gap-3 px-6 py-4 border-b border-n-weak"
    >
      <Button
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-arrow-left"
        :label="t('CRM.REPORTS.BACK_TO_BOARD')"
        @click="openBoard"
      />
      <h1 class="text-lg font-medium text-n-slate-12">
        {{ t('CRM.REPORTS.TITLE') }}
      </h1>
      <Select
        v-model="selectedPipelineId"
        :options="pipelineOptions"
        :placeholder="t('CRM.PIPELINE.SELECT')"
        :disabled="uiFlags.fetchingPipelines"
      />
      <Select v-model="dateRangeKey" :options="dateRangeOptions" />
      <Button
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-download"
        :label="t('CRM.REPORTS.EXPORT_CSV')"
        :is-loading="uiFlags.exporting"
        :disabled="uiFlags.exporting"
        @click="exportDeals"
      />
      <Spinner v-if="store.isFetching" :size="16" class="text-n-slate-11" />
    </header>

    <div
      v-if="store.hasMixedCurrencies"
      class="flex items-start gap-2 px-6 py-2 bg-n-amber-3 text-n-amber-11"
    >
      <Icon
        icon="i-lucide-triangle-alert"
        class="flex-shrink-0 mt-0.5 size-4"
      />
      <span class="text-sm">
        {{
          t('CRM.REPORTS.MIXED_CURRENCIES', {
            currencies: store.getAccountCurrencies.join(', '),
          })
        }}
      </span>
    </div>

    <div
      v-if="hasNoPipeline"
      class="flex items-center justify-center flex-1 text-sm text-n-slate-11"
    >
      {{ t('CRM.REPORTS.NO_PIPELINE') }}
    </div>

    <div v-else class="flex flex-col gap-4 px-6 py-4">
      <p class="text-xs text-n-slate-10">
        {{
          store.hasMixedCurrencies
            ? t('CRM.REPORTS.CURRENCY_NOTE_MIXED')
            : t('CRM.REPORTS.CURRENCY_NOTE', { currency: store.getCurrency })
        }}
      </p>

      <ReportBlock
        highlighted
        :title="t('CRM.REPORTS.FUNNEL.TITLE')"
        :description="t('CRM.REPORTS.FUNNEL.DESCRIPTION')"
        :empty-label="t('CRM.REPORTS.FUNNEL.EMPTY')"
        :is-loading="uiFlags.fetchingFunnel"
        :is-empty="!hasFunnelData"
      >
        <FunnelReport :rows="store.getFunnel" />
      </ReportBlock>

      <ReportBlock
        highlighted
        :title="t('CRM.REPORTS.SOURCES.TITLE')"
        :description="t('CRM.REPORTS.SOURCES.DESCRIPTION')"
        :empty-label="t('CRM.REPORTS.SOURCES.EMPTY')"
        :is-loading="uiFlags.fetchingSources"
        :is-empty="!store.getSources.length"
      >
        <SourcesReport :rows="store.getSources" />
      </ReportBlock>

      <ReportBlock
        :title="t('CRM.REPORTS.FORECAST.TITLE')"
        :description="t('CRM.REPORTS.FORECAST.DESCRIPTION')"
        :hint="
          store.isRangeInThePast ? t('CRM.REPORTS.FORECAST.PAST_RANGE') : ''
        "
        :empty-label="t('CRM.REPORTS.FORECAST.EMPTY')"
        :is-loading="uiFlags.fetchingForecast"
        :is-empty="!store.getForecast.length"
      >
        <ForecastReport :rows="store.getForecast" />
      </ReportBlock>

      <ReportBlock
        :title="t('CRM.REPORTS.LOSS_REASONS.TITLE')"
        :description="t('CRM.REPORTS.LOSS_REASONS.DESCRIPTION')"
        :empty-label="t('CRM.REPORTS.LOSS_REASONS.EMPTY')"
        :is-loading="uiFlags.fetchingLossReasons"
        :is-empty="!store.getLossReasons.length"
      >
        <LossReasonsReport :rows="store.getLossReasons" />
      </ReportBlock>

      <div class="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <ReportBlock
          :title="t('CRM.REPORTS.SALES_CYCLE.TITLE')"
          :description="t('CRM.REPORTS.SALES_CYCLE.DESCRIPTION')"
          :empty-label="t('CRM.REPORTS.SALES_CYCLE.EMPTY')"
          :is-loading="uiFlags.fetchingSalesCycle"
          :is-empty="!hasSalesCycle"
        >
          <SalesCycleSummary :sales-cycle="salesCycle" />
        </ReportBlock>

        <ReportBlock
          :title="t('CRM.REPORTS.STAGE_DURATIONS.TITLE')"
          :description="t('CRM.REPORTS.STAGE_DURATIONS.DESCRIPTION')"
          :empty-label="t('CRM.REPORTS.STAGE_DURATIONS.EMPTY')"
          :is-loading="uiFlags.fetchingStageDurations"
          :is-empty="!hasStageDurations"
        >
          <StageDurationsReport :rows="store.getStageDurations" />
        </ReportBlock>
      </div>
    </div>
  </main>
</template>
