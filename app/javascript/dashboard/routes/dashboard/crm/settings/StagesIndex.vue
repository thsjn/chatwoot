<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Draggable from 'vuedraggable';

import { useAlert } from 'dashboard/composables';
import { useCrmSettingsStore } from 'dashboard/store/crm/settings';

import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import StageDialog from './components/StageDialog.vue';

// Same token map as the board column, written as literals so the Tailwind scanner emits them.
const STAGE_ACCENT_CLASSES = {
  slate: 'bg-n-slate-9',
  blue: 'bg-n-blue-9',
  emerald: 'bg-n-teal-9',
  amber: 'bg-n-amber-9',
  ruby: 'bg-n-ruby-9',
  violet: 'bg-n-violet-9',
};

const CATEGORY_CLASSES = {
  open: 'bg-n-blue-9/10 text-n-blue-11',
  won: 'bg-n-teal-9/10 text-n-teal-11',
  lost: 'bg-n-ruby-9/10 text-n-ruby-11',
};

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const settingsStore = useCrmSettingsStore();

const dialogRef = ref(null);
const showDeleteModal = ref(false);
const selectedStage = ref({});

// The pipeline being edited travels in the query string so the screen is linkable from the
// pipeline list and survives a reload.
const pipelineId = computed({
  get: () => Number(route.query.pipeline_id) || null,
  set: value =>
    router.replace({
      name: 'crm_settings_stages',
      params: { accountId: route.params.accountId },
      query: { pipeline_id: value },
    }),
});

const pipelines = computed(() => settingsStore.getPipelines);
const stages = computed(() => settingsStore.getStages);
const uiFlags = computed(() => settingsStore.getUIFlags);

const pipelineOptions = computed(() =>
  pipelines.value.map(pipeline => ({
    value: pipeline.id,
    label: pipeline.name,
  }))
);

const openDeleteModal = stage => {
  selectedStage.value = stage;
  showDeleteModal.value = true;
};

const closeDeleteModal = () => {
  showDeleteModal.value = false;
};

// A stage still holding deals is refused with a 422 (`restrict_with_error`), so the reason the
// backend produced is what the user reads.
const confirmDeletion = async () => {
  const stage = selectedStage.value;
  showDeleteModal.value = false;
  try {
    await settingsStore.deleteStage(pipelineId.value, stage.id);
    useAlert(t('CRM.SETTINGS.STAGES.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(
      error.response?.data?.message || t('CRM.SETTINGS.STAGES.DELETE_ERROR')
    );
  }
};

const handleReorder = async event => {
  try {
    await settingsStore.reorderStages(pipelineId.value, event);
  } catch (error) {
    useAlert(t('CRM.SETTINGS.STAGES.REORDER_ERROR'));
    await settingsStore.fetchStages(pipelineId.value);
  }
};

watch(
  pipelineId,
  id => {
    if (id) settingsStore.fetchStages(id);
  },
  { immediate: true }
);

onMounted(async () => {
  const list = await settingsStore.fetchPipelines();
  if (pipelineId.value || !list.length) return;

  pipelineId.value = (list.find(item => item.is_default) || list[0]).id;
});
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.fetchingStages"
    :loading-message="t('CRM.SETTINGS.STAGES.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('CRM.SETTINGS.STAGES.HEADER')"
        :description="t('CRM.SETTINGS.STAGES.DESCRIPTION')"
      >
        <template #actions>
          <Select
            v-model="pipelineId"
            :options="pipelineOptions"
            :placeholder="t('CRM.PIPELINE.SELECT')"
          />
          <Button
            size="sm"
            icon="i-lucide-plus"
            :label="t('CRM.SETTINGS.STAGES.NEW')"
            :disabled="!pipelineId"
            @click="dialogRef?.open()"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <p
        v-if="!stages.length"
        class="py-10 text-sm text-center text-n-slate-11"
      >
        {{ t('CRM.SETTINGS.STAGES.EMPTY') }}
      </p>
      <Draggable
        v-else
        :model-value="stages"
        item-key="id"
        handle=".stage-drag-handle"
        ghost-class="opacity-40"
        class="flex flex-col gap-2"
        @update:model-value="handleReorder"
      >
        <template #item="{ element: stage }">
          <div
            class="flex items-center gap-3 px-4 py-3 border rounded-xl bg-n-solid-1 border-n-weak"
          >
            <span
              class="cursor-grab stage-drag-handle text-n-slate-10"
              :aria-label="t('CRM.SETTINGS.STAGES.DRAG_HANDLE')"
            >
              <Icon icon="i-lucide-grip-vertical" class="size-4" />
            </span>
            <span
              class="flex-shrink-0 rounded-full size-2"
              :class="STAGE_ACCENT_CLASSES[stage.color]"
            />
            <div class="flex flex-col min-w-0">
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ stage.name }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{
                  t('CRM.SETTINGS.STAGES.SUMMARY', {
                    probability: stage.probability,
                    rotting:
                      stage.rotting_days || t('CRM.SETTINGS.STAGES.NONE'),
                    wip: stage.wip_limit || t('CRM.SETTINGS.STAGES.NONE'),
                  })
                }}
              </span>
            </div>

            <span
              v-if="stage.is_entry"
              class="px-1.5 py-0.5 text-xs font-medium rounded-md bg-n-alpha-2 text-n-slate-11"
            >
              {{ t('CRM.SETTINGS.STAGES.ENTRY_BADGE') }}
            </span>
            <span
              class="px-1.5 py-0.5 text-xs font-medium rounded-md"
              :class="CATEGORY_CLASSES[stage.category]"
            >
              {{
                t(
                  `CRM.SETTINGS.STAGES.CATEGORY.${stage.category.toUpperCase()}`
                )
              }}
            </span>

            <div class="flex items-center gap-3 ms-auto">
              <Button
                v-tooltip.top="t('CRM.SETTINGS.EDIT')"
                slate
                sm
                icon="i-woot-edit-pen"
                @click="dialogRef?.open(stage)"
              />
              <Button
                v-tooltip.top="t('CRM.SETTINGS.DELETE')"
                slate
                sm
                icon="i-woot-bin"
                class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                @click="openDeleteModal(stage)"
              />
            </div>
          </div>
        </template>
      </Draggable>
    </template>

    <StageDialog v-if="pipelineId" ref="dialogRef" :pipeline-id="pipelineId" />

    <woot-delete-modal
      v-model:show="showDeleteModal"
      :on-close="closeDeleteModal"
      :on-confirm="confirmDeletion"
      :title="t('CRM.SETTINGS.STAGES.DELETE_TITLE')"
      :message="t('CRM.SETTINGS.STAGES.DELETE_MESSAGE')"
      :message-value="` ${selectedStage.name}?`"
      :confirm-text="t('CRM.SETTINGS.DELETE')"
      :reject-text="t('CRM.SETTINGS.CANCEL')"
    />
  </SettingsLayout>
</template>
