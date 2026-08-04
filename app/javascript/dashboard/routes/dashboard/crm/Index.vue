<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useDebounceFn } from '@vueuse/core';
import {
  addDays,
  endOfMonth,
  endOfWeek,
  format,
  startOfMonth,
  startOfWeek,
  subDays,
} from 'date-fns';

import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import {
  useCrmBoardStore,
  LOST_REASON_ERRORS,
} from 'dashboard/store/crm/board';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import BoardColumn from './components/BoardColumn.vue';
import DealDrawer from './components/DealDrawer.vue';
import DealFormModal from './components/DealFormModal.vue';
import LostReasonModal from './components/LostReasonModal.vue';

const SEARCH_DEBOUNCE_MS = 400;

const ISO_DATE = 'yyyy-MM-dd';
const toISODate = date => format(date, ISO_DATE);

/**
 * Presets keep the filter bar to a single control instead of a pair of date pickers. Each one
 * resolves to the `expected_close_since`/`expected_close_until` window the deals index filters
 * `expected_close_on` by; an open end simply omits its side of the range.
 */
const CLOSE_PERIODS = {
  overdue: () => ({
    expected_close_until: toISODate(subDays(new Date(), 1)),
  }),
  this_week: () => ({
    expected_close_since: toISODate(startOfWeek(new Date())),
    expected_close_until: toISODate(endOfWeek(new Date())),
  }),
  this_month: () => ({
    expected_close_since: toISODate(startOfMonth(new Date())),
    expected_close_until: toISODate(endOfMonth(new Date())),
  }),
  next_30_days: () => ({
    expected_close_since: toISODate(new Date()),
    expected_close_until: toISODate(addDays(new Date(), 30)),
  }),
};

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useCrmBoardStore();
const rootStore = useStore();
// The funnel configuration is administrator only (`Crm::PipelinePolicy` and friends), so the
// entry point is hidden instead of leaving an agent to discover it through a 401.
const { isAdmin } = useAdmin();

const agents = useMapGetter('agents/getAgents');

const dealFormRef = ref(null);
const searchQuery = ref('');
const sourceId = ref('');
const status = ref('');
const ownerId = ref('');
const closePeriod = ref('');
const selectedDealId = ref(null);

const uiFlags = computed(() => store.getUIFlags);
const showArchived = computed(() => store.getShowArchived);
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

const ownerOptions = computed(() => [
  { value: '', label: t('CRM.FILTERS.ALL_OWNERS') },
  ...agents.value.map(agent => ({
    value: agent.id,
    label: agent.available_name || agent.name,
  })),
]);

const closePeriodOptions = computed(() => [
  { value: '', label: t('CRM.FILTERS.ALL_CLOSE_PERIODS') },
  { value: 'overdue', label: t('CRM.FILTERS.CLOSE_PERIOD.OVERDUE') },
  { value: 'this_week', label: t('CRM.FILTERS.CLOSE_PERIOD.THIS_WEEK') },
  { value: 'this_month', label: t('CRM.FILTERS.CLOSE_PERIOD.THIS_MONTH') },
  { value: 'next_30_days', label: t('CRM.FILTERS.CLOSE_PERIOD.NEXT_30_DAYS') },
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
  if (!moveError || LOST_REASON_ERRORS.includes(moveError.code)) return null;

  return moveError.messageKey;
});

const isEmptyBoard = computed(
  () => !uiFlags.value.fetchingDeals && !stages.value.length
);

// Stages resolve before their cards do (`selectPipeline` awaits `fetchStages` then
// `fetchBoardDeals`), so right after picking a pipeline the columns exist but every one
// of them is empty. Without this, each column would flash its own "no deals" message
// before the first page lands — this is the one moment `CRM.BOARD.LOADING` earns its
// keep, distinguishing "still loading" from "genuinely empty stage".
const hasLoadedAnyDeal = computed(() =>
  stages.value.some(stage => store.getDealsByStage(stage.id).length)
);
const isBoardLoading = computed(
  () => uiFlags.value.fetchingDeals && !hasLoadedAnyDeal.value
);

const applyFilters = useDebounceFn(() => {
  store.setFilters({
    ...(searchQuery.value.trim() ? { q: searchQuery.value.trim() } : {}),
    ...(sourceId.value ? { source_id: sourceId.value } : {}),
    ...(status.value ? { status: status.value } : {}),
    ...(ownerId.value ? { owner_id: ownerId.value } : {}),
    ...(closePeriod.value ? CLOSE_PERIODS[closePeriod.value]() : {}),
  });
}, SEARCH_DEBOUNCE_MS);

watch([searchQuery, sourceId, status, ownerId, closePeriod], applyFilters);

const toggleArchived = () => store.setShowArchived(!showArchived.value);

// The column plus button says which stage the card belongs to; the header button leaves it to
// the form, which falls back to the first column of the board.
const openDealForm = (stageId = null) => dealFormRef.value?.open(stageId);

const openSettings = () =>
  router.push({
    name: 'crm_settings_pipelines',
    params: { accountId: route.params.accountId },
  });

// The funnel metrics are reachable from the board itself: the reports live on
// their own screen and nothing in the upstream sidebar points at them.
const openReports = () =>
  router.push({
    name: 'crm_reports',
    params: { accountId: route.params.accountId },
  });

onMounted(async () => {
  rootStore.dispatch('agents/get');

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
      <Select v-model="ownerId" :options="ownerOptions" />
      <Select v-model="closePeriod" :options="closePeriodOptions" />
      <Button
        v-if="!showArchived"
        size="sm"
        color="blue"
        icon="i-lucide-plus"
        :label="t('CRM.BOARD.ADD_DEAL')"
        :disabled="!stages.length"
        @click="openDealForm()"
      />
      <Button
        v-if="isAdmin"
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-settings"
        :label="t('CRM.SETTINGS.MANAGE')"
        @click="openSettings"
      />
      <Button
        size="sm"
        :variant="showArchived ? 'solid' : 'faded'"
        color="slate"
        icon="i-lucide-archive"
        :label="
          showArchived
            ? t('CRM.BOARD.BACK_TO_BOARD')
            : t('CRM.BOARD.SHOW_ARCHIVED')
        "
        @click="toggleArchived"
      />
      <Button
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-chart-no-axes-column"
        :label="t('CRM.REPORTS.TITLE')"
        @click="openReports"
      />
      <Spinner
        v-if="uiFlags.fetchingDeals || uiFlags.movingDeal"
        :size="16"
        class="text-n-slate-11"
      />
    </header>

    <div
      v-if="showArchived"
      class="flex items-center gap-2 px-6 py-2 bg-n-amber-3 text-n-amber-11"
    >
      <Icon icon="i-lucide-archive" class="flex-shrink-0 size-4" />
      <span class="text-sm">{{ t('CRM.BOARD.ARCHIVED_HINT') }}</span>
    </div>

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
    <div
      v-else-if="isBoardLoading"
      class="flex items-center justify-center flex-1 text-sm text-n-slate-11"
    >
      {{ t('CRM.BOARD.LOADING') }}
    </div>
    <div v-else class="flex flex-1 min-h-0 gap-4 px-6 py-4 overflow-x-auto">
      <BoardColumn
        v-for="stage in stages"
        :key="stage.id"
        :stage="stage"
        @select-deal="selectedDealId = $event"
        @add-deal="openDealForm"
      />
    </div>

    <DealDrawer
      v-if="selectedDealId"
      :deal-id="selectedDealId"
      @close="selectedDealId = null"
    />

    <DealFormModal ref="dealFormRef" />

    <LostReasonModal />
  </main>
</template>
