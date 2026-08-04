<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import {
  useCrmSettingsStore,
  STAGE_CATEGORIES,
  STAGE_COLORS,
} from 'dashboard/store/crm/settings';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const props = defineProps({
  pipelineId: { type: [Number, String], required: true },
});

const emit = defineEmits(['saved']);

const { t } = useI18n();
const settingsStore = useCrmSettingsStore();

const dialogRef = ref(null);
const editingId = ref(null);
const isSaving = ref(false);

const name = ref('');
const category = ref('open');
const color = ref('slate');
const probability = ref(0);
const rottingDays = ref('');
const wipLimit = ref('');
const isEntry = ref(false);

const isEditing = computed(() => !!editingId.value);
const isInvalid = computed(() => !name.value.trim());

const categoryOptions = computed(() =>
  STAGE_CATEGORIES.map(value => ({
    value,
    label: t(`CRM.SETTINGS.STAGES.CATEGORY.${value.toUpperCase()}`),
  }))
);

const colorOptions = computed(() =>
  STAGE_COLORS.map(value => ({
    value,
    label: t(`CRM.SETTINGS.STAGES.COLOR.${value.toUpperCase()}`),
  }))
);

const open = (stage = null) => {
  editingId.value = stage?.id || null;
  name.value = stage?.name || '';
  category.value = stage?.category || 'open';
  color.value = stage?.color || 'slate';
  probability.value = stage?.probability ?? 0;
  rottingDays.value = stage?.rotting_days ?? '';
  wipLimit.value = stage?.wip_limit ?? '';
  isEntry.value = !!stage?.is_entry;

  dialogRef.value?.open();
};

// `rotting_days` and `wip_limit` are validated as "greater than zero, or nothing at all", so an
// empty field has to travel as null instead of 0 — which the backend would reject.
const optionalNumber = value => {
  const number = Number(value);
  return value === '' || Number.isNaN(number) || number <= 0 ? null : number;
};

const submit = async () => {
  if (isInvalid.value) return;

  const payload = {
    name: name.value.trim(),
    category: category.value,
    color: color.value,
    probability: Number(probability.value) || 0,
    rotting_days: optionalNumber(rottingDays.value),
    wip_limit: optionalNumber(wipLimit.value),
    is_entry: isEntry.value,
  };

  isSaving.value = true;
  try {
    if (isEditing.value) {
      await settingsStore.updateStage(
        props.pipelineId,
        editingId.value,
        payload
      );
    } else {
      // A new column lands at the end of the pipeline, which is where the list shows it.
      await settingsStore.createStage(props.pipelineId, {
        ...payload,
        position: settingsStore.getStages.length,
      });
    }

    useAlert(t('CRM.SETTINGS.STAGES.SAVE_SUCCESS'));
    emit('saved');
    dialogRef.value?.close();
  } catch (error) {
    useAlert(
      error.response?.data?.message || t('CRM.SETTINGS.STAGES.SAVE_ERROR')
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
    width="lg"
    overflow-y-auto
    :title="
      isEditing
        ? t('CRM.SETTINGS.STAGES.EDIT_TITLE')
        : t('CRM.SETTINGS.STAGES.NEW_TITLE')
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
          {{ t('CRM.SETTINGS.STAGES.NAME') }}
        </span>
        <Input
          v-model="name"
          size="sm"
          :placeholder="t('CRM.SETTINGS.STAGES.NAME_PLACEHOLDER')"
        />
      </label>

      <div class="grid grid-cols-2 gap-4">
        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CRM.SETTINGS.STAGES.CATEGORY_LABEL') }}
          </span>
          <Select
            v-model="category"
            class="!w-full [&_select]:w-full"
            :options="categoryOptions"
          />
          <span class="text-xs text-n-slate-10">
            {{ t('CRM.SETTINGS.STAGES.CATEGORY_HINT') }}
          </span>
        </label>

        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CRM.SETTINGS.STAGES.COLOR_LABEL') }}
          </span>
          <Select
            v-model="color"
            class="!w-full [&_select]:w-full"
            :options="colorOptions"
          />
        </label>

        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CRM.SETTINGS.STAGES.PROBABILITY') }}
          </span>
          <Input
            v-model="probability"
            type="number"
            size="sm"
            min="0"
            max="100"
          />
        </label>

        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CRM.SETTINGS.STAGES.ROTTING_DAYS') }}
          </span>
          <Input
            v-model="rottingDays"
            type="number"
            size="sm"
            min="1"
            :placeholder="t('CRM.SETTINGS.STAGES.OPTIONAL')"
          />
          <span class="text-xs text-n-slate-10">
            {{ t('CRM.SETTINGS.STAGES.ROTTING_DAYS_HINT') }}
          </span>
        </label>

        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CRM.SETTINGS.STAGES.WIP_LIMIT') }}
          </span>
          <Input
            v-model="wipLimit"
            type="number"
            size="sm"
            min="1"
            :placeholder="t('CRM.SETTINGS.STAGES.OPTIONAL')"
          />
          <span class="text-xs text-n-slate-10">
            {{ t('CRM.SETTINGS.STAGES.WIP_LIMIT_HINT') }}
          </span>
        </label>
      </div>

      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <p class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('CRM.SETTINGS.STAGES.IS_ENTRY') }}
          </p>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('CRM.SETTINGS.STAGES.IS_ENTRY_HINT') }}
          </p>
        </div>
        <Switch v-model="isEntry" />
      </div>
    </div>
  </Dialog>
</template>
