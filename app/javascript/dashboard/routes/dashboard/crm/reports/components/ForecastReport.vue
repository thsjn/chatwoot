<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { format, parseISO } from 'date-fns';

import BarChart from 'shared/components/charts/BarChart.vue';
import ChartLegend from './ChartLegend.vue';
import { useCrmReportFormat } from '../composables/useCrmReportFormat';
import { CHART_COLORS, buildBarChartOptions } from '../helpers/chart';

const props = defineProps({
  rows: { type: Array, required: true },
});

const { t } = useI18n();
const { formatMoney, formatNumber } = useCrmReportFormat();

// `period` is the first day of the month, and it is null for the open deals
// that still have no expected close date — real money with no date yet.
const labelFor = row =>
  row.period
    ? format(parseISO(row.period), 'MMM yyyy')
    : t('CRM.REPORTS.FORECAST.NO_DATE');

const collection = computed(() => ({
  labels: props.rows.map(labelFor),
  datasets: [
    {
      label: t('CRM.REPORTS.FORECAST.WEIGHTED'),
      backgroundColor: CHART_COLORS.primary,
      data: props.rows.map(row => row.weighted_value_cents),
    },
    {
      label: t('CRM.REPORTS.FORECAST.GROSS'),
      backgroundColor: CHART_COLORS.muted,
      data: props.rows.map(row => row.value_cents),
    },
  ],
}));

const chartOptions = computed(() =>
  buildBarChartOptions({ formatValue: formatMoney })
);

const legendItems = computed(() => [
  { label: t('CRM.REPORTS.FORECAST.WEIGHTED'), color: 'primary' },
  { label: t('CRM.REPORTS.FORECAST.GROSS'), color: 'muted' },
]);

const totals = computed(() =>
  props.rows.reduce(
    (accumulator, row) => ({
      deals: accumulator.deals + row.deals_count,
      gross: accumulator.gross + row.value_cents,
      weighted: accumulator.weighted + row.weighted_value_cents,
    }),
    { deals: 0, gross: 0, weighted: 0 }
  )
);
</script>

<template>
  <div class="flex flex-col gap-5">
    <ChartLegend :items="legendItems" />
    <div class="h-64">
      <BarChart :collection="collection" :chart-options="chartOptions" />
    </div>

    <div class="overflow-x-auto">
      <table class="w-full text-sm text-start">
        <thead class="text-xs uppercase text-n-slate-11">
          <tr>
            <th class="py-2 pe-4 font-medium text-start">
              {{ t('CRM.REPORTS.FORECAST.PERIOD') }}
            </th>
            <th class="py-2 pe-4 font-medium text-end">
              {{ t('CRM.REPORTS.FORECAST.DEALS') }}
            </th>
            <th class="py-2 pe-4 font-medium text-end">
              {{ t('CRM.REPORTS.FORECAST.GROSS') }}
            </th>
            <th class="py-2 font-medium text-end">
              {{ t('CRM.REPORTS.FORECAST.WEIGHTED') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in rows"
            :key="row.period || 'no-date'"
            class="border-t border-n-weak"
          >
            <td class="py-2 pe-4 text-n-slate-12">{{ labelFor(row) }}</td>
            <td class="py-2 pe-4 text-end text-n-slate-11">
              {{ formatNumber(row.deals_count) }}
            </td>
            <td class="py-2 pe-4 text-end text-n-slate-11">
              {{ formatMoney(row.value_cents) }}
            </td>
            <td class="py-2 font-medium text-end text-n-slate-12">
              {{ formatMoney(row.weighted_value_cents) }}
            </td>
          </tr>
        </tbody>
        <tfoot class="text-sm border-t border-n-strong">
          <tr>
            <td class="py-2 pe-4 font-medium text-n-slate-12">
              {{ t('CRM.REPORTS.FORECAST.TOTAL') }}
            </td>
            <td class="py-2 pe-4 text-end text-n-slate-11">
              {{ formatNumber(totals.deals) }}
            </td>
            <td class="py-2 pe-4 text-end text-n-slate-11">
              {{ formatMoney(totals.gross) }}
            </td>
            <td class="py-2 font-medium text-end text-n-slate-12">
              {{ formatMoney(totals.weighted) }}
            </td>
          </tr>
        </tfoot>
      </table>
    </div>
  </div>
</template>
