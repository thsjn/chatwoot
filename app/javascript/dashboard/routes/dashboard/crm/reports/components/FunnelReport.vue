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
const { formatNumber, formatPercent } = useCrmReportFormat();

const collection = computed(() => ({
  labels: props.rows.map(row => row.name),
  datasets: [
    {
      label: t('CRM.REPORTS.FUNNEL.ENTERED'),
      backgroundColor: CHART_COLORS.primary,
      data: props.rows.map(row => row.entered_count),
    },
    {
      label: t('CRM.REPORTS.FUNNEL.ADVANCED'),
      backgroundColor: CHART_COLORS.muted,
      data: props.rows.map(row => row.advanced_count),
    },
  ],
}));

const chartOptions = buildBarChartOptions();

const legendItems = computed(() => [
  { label: t('CRM.REPORTS.FUNNEL.ENTERED'), color: 'primary' },
  { label: t('CRM.REPORTS.FUNNEL.ADVANCED'), color: 'muted' },
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
              {{ t('CRM.REPORTS.FUNNEL.STAGE') }}
            </th>
            <th class="py-2 pe-4 font-medium text-end">
              {{ t('CRM.REPORTS.FUNNEL.ENTERED') }}
            </th>
            <th class="py-2 pe-4 font-medium text-end">
              {{ t('CRM.REPORTS.FUNNEL.ADVANCED') }}
            </th>
            <th class="py-2 font-medium text-end">
              {{ t('CRM.REPORTS.FUNNEL.CONVERSION') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in rows"
            :key="row.stage_id"
            class="border-t border-n-weak"
          >
            <td class="py-2 pe-4 text-n-slate-12">{{ row.name }}</td>
            <td class="py-2 pe-4 text-end text-n-slate-12">
              {{ formatNumber(row.entered_count) }}
            </td>
            <td class="py-2 pe-4 text-end text-n-slate-11">
              {{ formatNumber(row.advanced_count) }}
            </td>
            <td class="py-2 font-medium text-end text-n-slate-12">
              {{ formatPercent(row.conversion_rate) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
