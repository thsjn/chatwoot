<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useCrmSettingsStore } from 'dashboard/store/crm/settings';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const emit = defineEmits(['saved']);

const { t } = useI18n();
const settingsStore = useCrmSettingsStore();

const dialogRef = ref(null);
const editingId = ref(null);
const isSaving = ref(false);

const name = ref('');
const position = ref(0);
const active = ref(true);

const isEditing = computed(() => !!editingId.value);
const isInvalid = computed(() => !name.value.trim());

const open = (lostReason = null) => {
  editingId.value = lostReason?.id || null;
  name.value = lostReason?.name || '';
  position.value = lostReason?.position ?? settingsStore.getLostReasons.length;
  active.value = lostReason ? !!lostReason.active : true;

  dialogRef.value?.open();
};

const submit = async () => {
  if (isInvalid.value) return;

  const payload = {
    name: name.value.trim(),
    position: Number(position.value) || 0,
    active: active.value,
  };

  isSaving.value = true;
  try {
    if (isEditing.value)
      await settingsStore.updateLostReason(editingId.value, payload);
    else await settingsStore.createLostReason(payload);

    useAlert(t('CRM.SETTINGS.LOST_REASONS.SAVE_SUCCESS'));
    emit('saved');
    dialogRef.value?.close();
  } catch (error) {
    useAlert(
      error.response?.data?.message || t('CRM.SETTINGS.LOST_REASONS.SAVE_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="md"
    :title="
      isEditing
        ? t('CRM.SETTINGS.LOST_REASONS.EDIT_TITLE')
        : t('CRM.SETTINGS.LOST_REASONS.NEW_TITLE')
    "
    :confirm-button-label="t('CRM.SETTINGS.SAVE')"
    :cancel-button-label="t('CRM.SETTINGS.CANCEL')"
    :disable-confirm-button="isInvalid"
    :is-loading="isSaving"
    @confirm="submit"
  >
    <div class="flex flex-col gap-4">
      <label class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CRM.SETTINGS.LOST_REASONS.NAME') }}
        </span>
        <Input
          v-model="name"
          size="sm"
          :placeholder="t('CRM.SETTINGS.LOST_REASONS.NAME_PLACEHOLDER')"
        />
      </label>

      <label class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CRM.SETTINGS.LOST_REASONS.POSITION') }}
        </span>
        <Input v-model="position" type="number" size="sm" min="0" />
        <span class="text-xs text-n-slate-10">
          {{ t('CRM.SETTINGS.LOST_REASONS.POSITION_HINT') }}
        </span>
      </label>

      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <p class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('CRM.SETTINGS.LOST_REASONS.ACTIVE') }}
          </p>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('CRM.SETTINGS.LOST_REASONS.ACTIVE_HINT') }}
          </p>
        </div>
        <Switch v-model="active" />
      </div>
    </div>
  </Dialog>
</template>
