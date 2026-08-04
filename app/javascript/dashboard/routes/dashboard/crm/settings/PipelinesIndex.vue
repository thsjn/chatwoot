<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useCrmSettingsStore } from 'dashboard/store/crm/settings';

import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import PipelineDialog from './components/PipelineDialog.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const settingsStore = useCrmSettingsStore();

const inboxes = useMapGetter('inboxes/getInboxes');

const dialogRef = ref(null);
const showDeleteModal = ref(false);
const selectedPipeline = ref({});
const deletingId = ref(null);

const pipelines = computed(() => settingsStore.getPipelines);
const uiFlags = computed(() => settingsStore.getUIFlags);

const tableHeaders = computed(() => [
  t('CRM.SETTINGS.PIPELINES.TABLE.NAME'),
  t('CRM.SETTINGS.PIPELINES.TABLE.INGESTION'),
  t('CRM.SETTINGS.PIPELINES.TABLE.CURRENCY'),
  t('CRM.SETTINGS.PIPELINES.TABLE.ACTION'),
]);

// The inbox names are what makes the ingestion column readable: an id list says nothing about
// which conversations are about to become cards.
const ingestionLabel = pipeline => {
  const ids = pipeline.settings?.inbox_ids || [];
  if (!ids.length) return t('CRM.SETTINGS.PIPELINES.INGESTION_OFF');

  return ids
    .map(
      id =>
        inboxes.value.find(inbox => inbox.id === Number(id))?.name || `#${id}`
    )
    .join(', ');
};

const openStages = pipeline =>
  router.push({
    name: 'crm_settings_stages',
    params: { accountId: route.params.accountId },
    query: { pipeline_id: pipeline.id },
  });

const openDeleteModal = pipeline => {
  selectedPipeline.value = pipeline;
  showDeleteModal.value = true;
};

const closeDeleteModal = () => {
  showDeleteModal.value = false;
};

// A pipeline that still holds deals comes back as a 422 carrying the reason, so the message the
// backend produced is the one shown instead of a generic failure.
const confirmDeletion = async () => {
  const pipeline = selectedPipeline.value;
  showDeleteModal.value = false;
  deletingId.value = pipeline.id;
  try {
    await settingsStore.deletePipeline(pipeline.id);
    useAlert(t('CRM.SETTINGS.PIPELINES.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(
      error.response?.data?.message || t('CRM.SETTINGS.PIPELINES.DELETE_ERROR')
    );
  } finally {
    deletingId.value = null;
  }
};

onMounted(() => {
  store.dispatch('inboxes/get');
  settingsStore.fetchPipelines();
});
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.fetchingPipelines"
    :loading-message="t('CRM.SETTINGS.PIPELINES.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('CRM.SETTINGS.PIPELINES.HEADER')"
        :description="t('CRM.SETTINGS.PIPELINES.DESCRIPTION')"
      >
        <template #actions>
          <Button
            size="sm"
            icon="i-lucide-plus"
            :label="t('CRM.SETTINGS.PIPELINES.NEW')"
            @click="dialogRef?.open()"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <BaseTable
        :headers="tableHeaders"
        :items="pipelines"
        :no-data-message="t('CRM.SETTINGS.PIPELINES.EMPTY')"
      >
        <template #row="{ items }">
          <BaseTableRow
            v-for="pipeline in items"
            :key="pipeline.id"
            :item="pipeline"
          >
            <template #default>
              <BaseTableCell>
                <div class="flex flex-col min-w-0">
                  <span
                    class="flex items-center gap-2 text-body-main text-n-slate-12"
                  >
                    {{ pipeline.name }}
                    <span
                      v-if="pipeline.is_default"
                      class="px-1.5 py-0.5 text-xs font-medium rounded-md bg-n-blue-3 text-n-blue-11"
                    >
                      {{ t('CRM.SETTINGS.PIPELINES.DEFAULT_BADGE') }}
                    </span>
                  </span>
                  <span class="text-xs truncate text-n-slate-11">
                    {{ pipeline.description }}
                  </span>
                </div>
              </BaseTableCell>

              <BaseTableCell>
                <span class="text-body-main text-n-slate-11">
                  {{ ingestionLabel(pipeline) }}
                </span>
              </BaseTableCell>

              <BaseTableCell>
                <span class="text-body-main text-n-slate-11">
                  {{ pipeline.settings?.moeda_padrao }}
                </span>
              </BaseTableCell>

              <BaseTableCell align="end">
                <div class="flex justify-end flex-shrink-0 gap-3">
                  <Button
                    slate
                    sm
                    faded
                    icon="i-lucide-columns-3"
                    :label="t('CRM.SETTINGS.PIPELINES.MANAGE_STAGES')"
                    @click="openStages(pipeline)"
                  />
                  <Button
                    v-tooltip.top="t('CRM.SETTINGS.EDIT')"
                    slate
                    sm
                    icon="i-woot-edit-pen"
                    @click="dialogRef?.open(pipeline)"
                  />
                  <Button
                    v-tooltip.top="t('CRM.SETTINGS.DELETE')"
                    slate
                    sm
                    icon="i-woot-bin"
                    class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                    :is-loading="deletingId === pipeline.id"
                    @click="openDeleteModal(pipeline)"
                  />
                </div>
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </template>

    <PipelineDialog ref="dialogRef" />

    <woot-delete-modal
      v-model:show="showDeleteModal"
      :on-close="closeDeleteModal"
      :on-confirm="confirmDeletion"
      :title="t('CRM.SETTINGS.PIPELINES.DELETE_TITLE')"
      :message="t('CRM.SETTINGS.PIPELINES.DELETE_MESSAGE')"
      :message-value="` ${selectedPipeline.name}?`"
      :confirm-text="t('CRM.SETTINGS.DELETE')"
      :reject-text="t('CRM.SETTINGS.CANCEL')"
    />
  </SettingsLayout>
</template>
