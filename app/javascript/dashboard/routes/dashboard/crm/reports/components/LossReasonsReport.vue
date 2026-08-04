<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import BarChart from 'shared/components/charts/BarChart.vue';
import { useCrmReportFormat } from '../composables/useCrmReportFormat';
import { CHART_COLORS, buildBarChartOptions } from '../helpers/chart';

const props = defineProps({
  rows: { type: Array, required: true },
});

const { t } = useI18n();
const { formatMoney, formatNumber } = useCrmReportFormat();

// Deals marked as lost without recording a reason come back under a null
// reason: they are the ones a manager wants to see first.
const labelFor = row =>
  row.lost_reason?.name || t('CRM.REPORTS.LOSS_REASONS.NO_REASON');

const collection = computed(() => ({
  labels: props.rows.map(labelFor),
  datasets: [
    {
      label: t('CRM.REPORTS.LOSS_REASONS.VALUE'),
      backgroundColor: CHART_COLORS.negative,
      data: props.rows.map(row => row.value_cents),
    },
  ],
}));

const chartOptions = computed(() =>
  buildBarChartOptions({ formatValue: formatMoney })
);
</script>

<template>
  <div class="flex flex-col gap-5">
    <div class="h-64">
      <BarChart :collection="collection" :chart-options="chartOptions" />
    </div>

    <div class="overflow-x-auto">
      <table class="w-full text-sm text-start">
        <thead class="text-xs uppercase text-n-slate-11">
          <tr>
            <th class="py-2 pe-4 font-medium text-start">
              {{ t('CRM.REPORTS.LOSS_REASONS.REASON') }}
            </th>
            <th class="py-2 pe-4 font-medium text-end">
              {{ t('CRM.REPORTS.LOSS_REASONS.DEALS') }}
            </th>
            <th class="py-2 font-medium text-end">
              {{ t('CRM.REPORTS.LOSS_REASONS.VALUE') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in rows"
            :key="row.lost_reason?.id || 'no-reason'"
            class="border-t border-n-weak"
          >
            <td class="py-2 pe-4 text-n-slate-12">{{ labelFor(row) }}</td>
            <td class="py-2 pe-4 text-end text-n-slate-11">
              {{ formatNumber(row.deals_count) }}
            </td>
            <td class="py-2 font-medium text-end text-n-slate-12">
              {{ formatMoney(row.value_cents) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
