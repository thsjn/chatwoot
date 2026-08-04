<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useCrmSettingsStore } from 'dashboard/store/crm/settings';

import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import SourceDialog from './components/SourceDialog.vue';

const { t } = useI18n();
const store = useStore();
const settingsStore = useCrmSettingsStore();

const inboxes = useMapGetter('inboxes/getInboxes');

const dialogRef = ref(null);

const sources = computed(() => settingsStore.getSources);
const uiFlags = computed(() => settingsStore.getUIFlags);

const tableHeaders = computed(() => [
  t('CRM.SETTINGS.SOURCES.TABLE.NAME'),
  t('CRM.SETTINGS.SOURCES.TABLE.KIND'),
  t('CRM.SETTINGS.SOURCES.TABLE.INBOX'),
  t('CRM.SETTINGS.SOURCES.TABLE.ACTIVE'),
  t('CRM.SETTINGS.SOURCES.TABLE.ACTION'),
]);

const inboxName = source =>
  inboxes.value.find(inbox => inbox.id === source.inbox_id)?.name || '—';

/**
 * Sources are retired, not deleted: the deals that already carry one keep pointing at it, and an
 * inactive source simply stops being offered in the pickers (the index hides it unless the
 * administration asks for `include_inactive`).
 */
const toggleActive = async source => {
  try {
    await settingsStore.updateSource(source.id, { active: !source.active });
    useAlert(t('CRM.SETTINGS.SOURCES.SAVE_SUCCESS'));
  } catch (error) {
    useAlert(t('CRM.SETTINGS.SOURCES.SAVE_ERROR'));
  }
};

onMounted(() => {
  store.dispatch('inboxes/get');
  settingsStore.fetchSources();
});
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.fetchingSources"
    :loading-message="t('CRM.SETTINGS.SOURCES.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('CRM.SETTINGS.SOURCES.HEADER')"
        :description="t('CRM.SETTINGS.SOURCES.DESCRIPTION')"
      >
        <template #actions>
          <Button
            size="sm"
            icon="i-lucide-plus"
            :label="t('CRM.SETTINGS.SOURCES.NEW')"
            @click="dialogRef?.open()"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <BaseTable
        :headers="tableHeaders"
        :items="sources"
        :no-data-message="t('CRM.SETTINGS.SOURCES.EMPTY')"
      >
        <template #row="{ items }">
          <BaseTableRow v-for="source in items" :key="source.id" :item="source">
            <template #default>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-12">
                  {{ source.name }}
                </span>
              </BaseTableCell>

              <BaseTableCell>
                <span class="text-body-main text-n-slate-11">
                  {{
                    t(`CRM.SETTINGS.SOURCES.KIND.${source.kind.toUpperCase()}`)
                  }}
                </span>
              </BaseTableCell>

              <BaseTableCell>
                <span class="text-body-main text-n-slate-11">
                  {{ inboxName(source) }}
                </span>
              </BaseTableCell>

              <BaseTableCell>
                <Switch
                  :model-value="source.active"
                  @change="toggleActive(source)"
                />
              </BaseTableCell>

              <BaseTableCell align="end">
                <Button
                  v-tooltip.top="t('CRM.SETTINGS.EDIT')"
                  slate
                  sm
                  icon="i-woot-edit-pen"
                  @click="dialogRef?.open(source)"
                />
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </template>

    <SourceDialog ref="dialogRef" />
  </SettingsLayout>
</template>
