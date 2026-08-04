<script setup>
import { useI18n } from 'vue-i18n';

import { useCrmReportFormat } from '../composables/useCrmReportFormat';

defineProps({
  rows: { type: Array, required: true },
});

const { t } = useI18n();
const { formatDuration, formatNumber } = useCrmReportFormat();
</script>

<template>
  <div class="overflow-x-auto">
    <table class="w-full text-sm text-start">
      <thead class="text-xs uppercase text-n-slate-11">
        <tr>
          <th class="py-2 pe-4 font-medium text-start">
            {{ t('CRM.REPORTS.STAGE_DURATIONS.STAGE') }}
          </th>
          <th class="py-2 pe-4 font-medium text-end">
            {{ t('CRM.REPORTS.STAGE_DURATIONS.AVERAGE') }}
          </th>
          <th class="py-2 font-medium text-end">
            {{ t('CRM.REPORTS.STAGE_DURATIONS.SAMPLE') }}
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
          <td class="py-2 pe-4 font-medium text-end text-n-slate-12">
            {{ formatDuration(row.avg_duration_seconds) }}
          </td>
          <td class="py-2 text-end text-n-slate-11">
            {{ formatNumber(row.transitions_count) }}
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
