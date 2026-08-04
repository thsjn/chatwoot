<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import ReportMetricCard from 'dashboard/routes/dashboard/settings/reports/components/ReportMetricCard.vue';
import { useCrmReportFormat } from '../composables/useCrmReportFormat';

const props = defineProps({
  salesCycle: { type: Object, required: true },
});

const { t } = useI18n();
const { formatDuration, formatNumber } = useCrmReportFormat();

// Won and lost are reported apart because they answer different questions: how
// long it takes to earn a customer, and how long the team burns on business it
// will not win. `deals_count` rides along as the sample behind the average.
const metrics = computed(() => [
  {
    key: 'WON_CYCLE',
    value: formatDuration(props.salesCycle.won?.avg_cycle_seconds),
  },
  {
    key: 'WON_DEALS',
    value: formatNumber(props.salesCycle.won?.deals_count),
  },
  {
    key: 'LOST_CYCLE',
    value: formatDuration(props.salesCycle.lost?.avg_cycle_seconds),
  },
  {
    key: 'LOST_DEALS',
    value: formatNumber(props.salesCycle.lost?.deals_count),
  },
]);
</script>

<template>
  <div class="grid grid-cols-2 gap-6 lg:grid-cols-4">
    <ReportMetricCard
      v-for="metric in metrics"
      :key="metric.key"
      :label="t(`CRM.REPORTS.SALES_CYCLE.${metric.key}.LABEL`)"
      :value="metric.value"
      :info-text="t(`CRM.REPORTS.SALES_CYCLE.${metric.key}.INFO`)"
    />
  </div>
</template>
