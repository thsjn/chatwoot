<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const accountId = computed(() => route.params.accountId);

const backToBoard = () =>
  router.push({ name: 'crm_board', params: { accountId: accountId.value } });

const tabs = computed(() => [
  { name: 'crm_settings_pipelines', label: t('CRM.SETTINGS.TABS.PIPELINES') },
  { name: 'crm_settings_stages', label: t('CRM.SETTINGS.TABS.STAGES') },
  { name: 'crm_settings_sources', label: t('CRM.SETTINGS.TABS.SOURCES') },
  {
    name: 'crm_settings_lost_reasons',
    label: t('CRM.SETTINGS.TABS.LOST_REASONS'),
  },
]);
</script>

<template>
  <main
    class="flex flex-col w-full h-full min-h-0 overflow-y-auto bg-n-background"
  >
    <header class="flex flex-col gap-4 px-6 pt-6">
      <div class="flex items-center justify-between gap-4">
        <h1 class="text-lg font-medium text-n-slate-12">
          {{ t('CRM.SETTINGS.TITLE') }}
        </h1>
        <Button
          faded
          slate
          size="sm"
          icon="i-lucide-arrow-left"
          :label="t('CRM.SETTINGS.BACK_TO_BOARD')"
          @click="backToBoard"
        />
      </div>

      <nav class="flex flex-wrap items-center gap-1 border-b border-n-weak">
        <router-link
          v-for="tab in tabs"
          :key="tab.name"
          :to="{ name: tab.name, params: { accountId } }"
          class="px-3 py-2 -mb-px text-sm font-medium border-b-2 rounded-t-md"
          :class="
            route.name === tab.name
              ? 'border-n-brand text-n-slate-12'
              : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
          "
        >
          {{ tab.label }}
        </router-link>
      </nav>
    </header>

    <div class="flex-1 min-h-0 px-6 py-4">
      <router-view />
    </div>
  </main>
</template>
