<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import BarChart from 'shared/components/charts/BarChart.vue';
import ChartLegend from './ChartLegend.vue';
import { useCrmReportFormat } from '../composables/useCrmReportFormat';
import { CHART_COLORS, buildBarChartOptions } from '../helpers/chart';

const props = defineProps({
  rows: { type: Array, required: true },
});

const { t } = useI18n();
const { formatMoney, formatNumber, formatPercent } = useCrmReportFormat();

// A deal closed without a channel tagged comes back under a null source, and
// that hole is exactly what this report is meant to expose.
const labelFor = row => row.source?.name || t('CRM.REPORTS.SOURCES.NO_SOURCE');

const collection = computed(() => ({
  labels: props.rows.map(labelFor),
  datasets: [
    {
      label: t('CRM.REPORTS.SOURCES.WON_VALUE'),
      backgroundColor: CHART_COLORS.positive,
      data: props.rows.map(row => row.won_value_cents),
    },
    {
      label: t('CRM.REPORTS.SOURCES.LOST_VALUE'),
      backgroundColor: CHART_COLORS.negative,
      data: props.rows.map(row => row.lost_value_cents),
    },
  ],
}));

const chartOptions = computed(() =>
  buildBarChartOptions({ formatValue: formatMoney })
);

const legendItems = computed(() => [
  { label: t('CRM.REPORTS.SOURCES.WON_VALUE'), color: 'positive' },
  { label: t('CRM.REPORTS.SOURCES.LOST_VALUE'), color: 'negative' },
]);
</script>

<template>
  <div class="flex flex-col gap-5">
    <ChartLegend :items="legendItems" />
    <div class="h-72">
      <BarChart :collection="collection" :chart-options="chartOptions" />
    </div>

    <div class="overflow-x-auto">
      <table class="w-full text-sm text-start">
        <thead class="text-xs uppercase text-n-slate-11">
          <tr>
            <th class="py-2 pe-4 font-medium text-start">
              {{ t('CRM.REPORTS.SOURCES.CHANNEL') }}
            </th>
            <th class="py-2 pe-4 font-medium text-end">
              {{ t('CRM.REPORTS.SOURCES.WON') }}
            </th>
            <th class="py-2 pe-4 font-medium text-end">
              {{ t('CRM.REPORTS.SOURCES.WON_VALUE') }}
            </th>
            <th class="py-2 pe-4 font-medium text-end">
              {{ t('CRM.REPORTS.SOURCES.LOST') }}
            </th>
            <th class="py-2 pe-4 font-medium text-end">
              {{ t('CRM.REPORTS.SOURCES.LOST_VALUE') }}
            </th>
            <th class="py-2 font-medium text-end">
              {{ t('CRM.REPORTS.SOURCES.WIN_RATE') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in rows"
            :key="row.source?.id || 'no-source'"
            class="border-t border-n-weak"
          >
            <td class="py-2 pe-4">
              <span class="text-n-slate-12">{{ labelFor(row) }}</span>
              <span
                v-if="row.source?.kind"
                class="ms-2 text-xs text-n-slate-10"
              >
                {{ row.source.kind }}
              </span>
            </td>
            <td class="py-2 pe-4 text-end text-n-slate-11">
              {{ formatNumber(row.won_count) }}
            </td>
            <td class="py-2 pe-4 font-medium text-end text-n-teal-11">
              {{ formatMoney(row.won_value_cents) }}
            </td>
            <td class="py-2 pe-4 text-end text-n-slate-11">
              {{ formatNumber(row.lost_count) }}
            </td>
            <td class="py-2 pe-4 text-end text-n-ruby-11">
              {{ formatMoney(row.lost_value_cents) }}
            </td>
            <td class="py-2 font-medium text-end text-n-slate-12">
              {{ formatPercent(row.win_rate) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
