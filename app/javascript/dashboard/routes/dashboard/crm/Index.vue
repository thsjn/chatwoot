<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';

import { useCrmBoardStore } from 'dashboard/store/crm/board';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import BoardColumn from './components/BoardColumn.vue';
import LostReasonModal from './components/LostReasonModal.vue';

const SEARCH_DEBOUNCE_MS = 400;

const { t } = useI18n();
const store = useCrmBoardStore();

const searchQuery = ref('');
const sourceId = ref('');
const status = ref('');

const uiFlags = computed(() => store.getUIFlags);
const stages = computed(() => store.getStages);
const selectedPipelineId = computed({
  get: () => store.getSelectedPipeline?.id ?? '',
  set: value => store.selectPipeline(value),
});

const pipelineOptions = computed(() =>
  store.getPipelines.map(pipeline => ({
    value: pipeline.id,
    label: pipeline.name,
  }))
);

const sourceOptions = computed(() => [
  { value: '', label: t('CRM.FILTERS.ALL_SOURCES') },
  ...store.getSources.map(source => ({
    value: source.id,
    label: source.name,
  })),
]);

const statusOptions = computed(() => [
  { value: '', label: t('CRM.FILTERS.ALL_STATUSES') },
  { value: 'open', label: t('CRM.FILTERS.STATUS.OPEN') },
  { value: 'won', label: t('CRM.FILTERS.STATUS.WON') },
  { value: 'lost', label: t('CRM.FILTERS.STATUS.LOST') },
]);

// The lost reason flow owns its own dialog, so the banner would only duplicate it.
const bannerMessageKey = computed(() => {
  const moveError = store.getMoveError;
  if (!moveError || moveError.code === 'lost_reason_required') return null;

  return moveError.messageKey;
});

const isEmptyBoard = computed(
  () => !uiFlags.value.fetchingDeals && !stages.value.length
);

const applyFilters = useDebounceFn(() => {
  store.setFilters({
    ...(searchQuery.value.trim() ? { q: searchQuery.value.trim() } : {}),
    ...(sourceId.value ? { source_id: sourceId.value } : {}),
    ...(status.value ? { status: status.value } : {}),
  });
}, SEARCH_DEBOUNCE_MS);

watch([searchQuery, sourceId, status], applyFilters);

onMounted(async () => {
  const [pipelines] = await Promise.all([
    store.fetchPipelines(),
    store.fetchLostReasons(),
    store.fetchSources(),
  ]);

  const pipeline = pipelines.find(item => item.is_default) || pipelines[0];
  if (pipeline) await store.selectPipeline(pipeline.id);
});
</script>

<template>
  <main class="flex flex-col w-full h-full min-h-0 bg-n-background">
    <header
      class="flex flex-wrap items-center gap-3 px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-lg font-medium text-n-slate-12">
        {{ t('CRM.BOARD.TITLE') }}
      </h1>
      <Select
        v-model="selectedPipelineId"
        :options="pipelineOptions"
        :placeholder="t('CRM.PIPELINE.SELECT')"
        :disabled="uiFlags.fetchingPipelines"
      />
      <Input
        v-model="searchQuery"
        size="sm"
        class="w-64"
        :placeholder="t('CRM.BOARD.SEARCH_PLACEHOLDER')"
      />
      <Select v-model="sourceId" :options="sourceOptions" />
      <Select v-model="status" :options="statusOptions" />
      <Spinner
        v-if="uiFlags.fetchingDeals || uiFlags.movingDeal"
        :size="16"
        class="text-n-slate-11"
      />
    </header>

    <div
      v-if="bannerMessageKey"
      class="flex items-center gap-2 px-6 py-2 bg-n-ruby-3 text-n-ruby-11"
    >
      <Icon icon="i-lucide-triangle-alert" class="flex-shrink-0 size-4" />
      <span class="text-sm">{{ t(bannerMessageKey) }}</span>
      <Button
        variant="link"
        color="ruby"
        size="sm"
        class="ms-auto"
        :label="t('CRM.BOARD.DISMISS')"
        @click="store.clearMoveError()"
      />
    </div>

    <div
      v-if="isEmptyBoard"
      class="flex items-center justify-center flex-1 text-sm text-n-slate-11"
    >
      {{ t('CRM.BOARD.EMPTY_STATE') }}
    </div>
    <div v-else class="flex flex-1 min-h-0 gap-4 px-6 py-4 overflow-x-auto">
      <BoardColumn v-for="stage in stages" :key="stage.id" :stage="stage" />
    </div>

    <LostReasonModal />
  </main>
</template>
