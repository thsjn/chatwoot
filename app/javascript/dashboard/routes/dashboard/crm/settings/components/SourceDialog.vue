<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import {
  useCrmSettingsStore,
  SOURCE_KINDS,
} from 'dashboard/store/crm/settings';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const emit = defineEmits(['saved']);

const { t } = useI18n();
const store = useStore();
const settingsStore = useCrmSettingsStore();

const inboxes = useMapGetter('inboxes/getInboxes');

const dialogRef = ref(null);
const editingId = ref(null);
const isSaving = ref(false);

const name = ref('');
const kind = ref('inbox');
const identifier = ref('');
const inboxId = ref('');
const active = ref(true);

const isEditing = computed(() => !!editingId.value);
const isInvalid = computed(() => !name.value.trim());

// Only the `inbox` kind carries an inbox: the other kinds describe where the lead came from
// outside Chatwoot (a landing page, an import, an n8n flow), so the field would mean nothing.
const isInboxKind = computed(() => kind.value === 'inbox');

const kindOptions = computed(() =>
  SOURCE_KINDS.map(value => ({
    value,
    label: t(`CRM.SETTINGS.SOURCES.KIND.${value.toUpperCase()}`),
  }))
);

const inboxOptions = computed(() => [
  { value: '', label: t('CRM.SETTINGS.SOURCES.NO_INBOX') },
  ...inboxes.value.map(inbox => ({ value: inbox.id, label: inbox.name })),
]);

const open = (source = null) => {
  editingId.value = source?.id || null;
  name.value = source?.name || '';
  kind.value = source?.kind || 'inbox';
  identifier.value = source?.identifier || '';
  inboxId.value = source?.inbox_id || '';
  active.value = source ? !!source.active : true;

  store.dispatch('inboxes/get');
  dialogRef.value?.open();
};

const submit = async () => {
  if (isInvalid.value) return;

  const payload = {
    name: name.value.trim(),
    kind: kind.value,
    identifier: identifier.value.trim(),
    active: active.value,
    inbox_id: isInboxKind.value ? inboxId.value || null : null,
  };

  isSaving.value = true;
  try {
    if (isEditing.value)
      await settingsStore.updateSource(editingId.value, payload);
    else await settingsStore.createSource(payload);

    useAlert(t('CRM.SETTINGS.SOURCES.SAVE_SUCCESS'));
    emit('saved');
    dialogRef.value?.close();
  } catch (error) {
    useAlert(
      error.response?.data?.message || t('CRM.SETTINGS.SOURCES.SAVE_ERROR')
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
        ? t('CRM.SETTINGS.SOURCES.EDIT_TITLE')
        : t('CRM.SETTINGS.SOURCES.NEW_TITLE')
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
          {{ t('CRM.SETTINGS.SOURCES.NAME') }}
        </span>
        <Input
          v-model="name"
          size="sm"
          :placeholder="t('CRM.SETTINGS.SOURCES.NAME_PLACEHOLDER')"
        />
      </label>

      <label class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CRM.SETTINGS.SOURCES.KIND_LABEL') }}
        </span>
        <Select
          v-model="kind"
          class="!w-full [&_select]:w-full"
          :options="kindOptions"
        />
      </label>

      <label v-if="isInboxKind" class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CRM.SETTINGS.SOURCES.INBOX') }}
        </span>
        <Select
          v-model="inboxId"
          class="!w-full [&_select]:w-full"
          :options="inboxOptions"
        />
        <span class="text-xs text-n-slate-10">
          {{ t('CRM.SETTINGS.SOURCES.INBOX_HINT') }}
        </span>
      </label>

      <label class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CRM.SETTINGS.SOURCES.IDENTIFIER') }}
        </span>
        <Input
          v-model="identifier"
          size="sm"
          :placeholder="t('CRM.SETTINGS.SOURCES.IDENTIFIER_PLACEHOLDER')"
        />
        <span class="text-xs text-n-slate-10">
          {{ t('CRM.SETTINGS.SOURCES.IDENTIFIER_HINT') }}
        </span>
      </label>

      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <p class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('CRM.SETTINGS.SOURCES.ACTIVE') }}
          </p>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('CRM.SETTINGS.SOURCES.ACTIVE_HINT') }}
          </p>
        </div>
        <Switch v-model="active" />
      </div>
    </div>
  </Dialog>
</template>
