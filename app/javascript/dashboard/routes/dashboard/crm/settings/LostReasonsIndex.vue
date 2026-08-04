<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
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
import LostReasonDialog from './components/LostReasonDialog.vue';

const { t } = useI18n();
const settingsStore = useCrmSettingsStore();

const dialogRef = ref(null);

const lostReasons = computed(() => settingsStore.getLostReasons);
const uiFlags = computed(() => settingsStore.getUIFlags);

const tableHeaders = computed(() => [
  t('CRM.SETTINGS.LOST_REASONS.TABLE.NAME'),
  t('CRM.SETTINGS.LOST_REASONS.TABLE.POSITION'),
  t('CRM.SETTINGS.LOST_REASONS.TABLE.ACTIVE'),
  t('CRM.SETTINGS.LOST_REASONS.TABLE.ACTION'),
]);

/**
 * Reasons are retired instead of deleted: `Crm::MoveDealService` rejects an inactive reason, so
 * turning one off removes it from the picker while the deals that already carry it keep their
 * history.
 */
const toggleActive = async lostReason => {
  try {
    await settingsStore.updateLostReason(lostReason.id, {
      active: !lostReason.active,
    });
    useAlert(t('CRM.SETTINGS.LOST_REASONS.SAVE_SUCCESS'));
  } catch (error) {
    useAlert(t('CRM.SETTINGS.LOST_REASONS.SAVE_ERROR'));
  }
};

onMounted(() => settingsStore.fetchLostReasons());
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.fetchingLostReasons"
    :loading-message="t('CRM.SETTINGS.LOST_REASONS.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('CRM.SETTINGS.LOST_REASONS.HEADER')"
        :description="t('CRM.SETTINGS.LOST_REASONS.DESCRIPTION')"
      >
        <template #actions>
          <Button
            size="sm"
            icon="i-lucide-plus"
            :label="t('CRM.SETTINGS.LOST_REASONS.NEW')"
            @click="dialogRef?.open()"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <BaseTable
        :headers="tableHeaders"
        :items="lostReasons"
        :no-data-message="t('CRM.SETTINGS.LOST_REASONS.EMPTY')"
      >
        <template #row="{ items }">
          <BaseTableRow
            v-for="lostReason in items"
            :key="lostReason.id"
            :item="lostReason"
          >
            <template #default>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-12">
                  {{ lostReason.name }}
                </span>
              </BaseTableCell>

              <BaseTableCell>
                <span class="text-body-main tabular-nums text-n-slate-11">
                  {{ lostReason.position }}
                </span>
              </BaseTableCell>

              <BaseTableCell>
                <Switch
                  :model-value="lostReason.active"
                  @change="toggleActive(lostReason)"
                />
              </BaseTableCell>

              <BaseTableCell align="end">
                <Button
                  v-tooltip.top="t('CRM.SETTINGS.EDIT')"
                  slate
                  sm
                  icon="i-woot-edit-pen"
                  @click="dialogRef?.open(lostReason)"
                />
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </template>

    <LostReasonDialog ref="dialogRef" />
  </SettingsLayout>
</template>
