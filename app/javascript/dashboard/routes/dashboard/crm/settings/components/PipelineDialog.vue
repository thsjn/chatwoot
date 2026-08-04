<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import {
  useCrmSettingsStore,
  buildPipelineSettings,
} from 'dashboard/store/crm/settings';

import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const emit = defineEmits(['saved']);

const { t } = useI18n();
const store = useStore();
const settingsStore = useCrmSettingsStore();

const inboxes = useMapGetter('inboxes/getInboxes');

const dialogRef = ref(null);
const editingId = ref(null);
const isSaving = ref(false);

const name = ref('');
const description = ref('');
const isDefault = ref(false);
const inboxIds = ref([]);
const dedupeDays = ref(30);
const requiresNextActivity = ref(false);
const currency = ref('BRL');
const restrictedByOwner = ref(false);

const isEditing = computed(() => !!editingId.value);
const isInvalid = computed(() => !name.value.trim());

// The whole point of the warning below: as long as no inbox is picked, no conversation is ever
// turned into a card. `Crm::IngestConversationService` only matches pipelines whose
// `settings['inbox_ids']` contains the inbox of the conversation.
const isIngestionEnabled = computed(() => inboxIds.value.length > 0);

const toggleInbox = inboxId => {
  inboxIds.value = inboxIds.value.includes(inboxId)
    ? inboxIds.value.filter(id => id !== inboxId)
    : [...inboxIds.value, inboxId];
};

const open = (pipeline = null) => {
  const settings = buildPipelineSettings(pipeline?.settings);

  editingId.value = pipeline?.id || null;
  name.value = pipeline?.name || '';
  description.value = pipeline?.description || '';
  isDefault.value = !!pipeline?.is_default;
  inboxIds.value = settings.inbox_ids;
  dedupeDays.value = settings.janela_dedupe_dias;
  requiresNextActivity.value = !!settings.exige_proxima_atividade;
  currency.value = settings.moeda_padrao;
  restrictedByOwner.value = !!settings.restrito_por_owner;

  store.dispatch('inboxes/get');
  dialogRef.value?.open();
};

// `settings` is written as a whole hash — `buildPipelineSettings` is what guarantees the four
// keys the form did not touch travel along instead of being dropped by the update.
const submit = async () => {
  if (isInvalid.value) return;

  const payload = {
    name: name.value.trim(),
    description: description.value.trim(),
    is_default: isDefault.value,
    settings: buildPipelineSettings({
      inbox_ids: inboxIds.value,
      janela_dedupe_dias: Number(dedupeDays.value) || 30,
      exige_proxima_atividade: requiresNextActivity.value,
      moeda_padrao: currency.value.trim().toUpperCase(),
      restrito_por_owner: restrictedByOwner.value,
    }),
  };

  isSaving.value = true;
  try {
    if (isEditing.value)
      await settingsStore.updatePipeline(editingId.value, payload);
    else await settingsStore.createPipeline(payload);

    useAlert(t('CRM.SETTINGS.PIPELINES.SAVE_SUCCESS'));
    emit('saved');
    dialogRef.value?.close();
  } catch (error) {
    useAlert(
      error.response?.data?.message || t('CRM.SETTINGS.PIPELINES.SAVE_ERROR')
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
    width="xl"
    overflow-y-auto
    :title="
      isEditing
        ? t('CRM.SETTINGS.PIPELINES.EDIT_TITLE')
        : t('CRM.SETTINGS.PIPELINES.NEW_TITLE')
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
          {{ t('CRM.SETTINGS.PIPELINES.NAME') }}
        </span>
        <Input
          v-model="name"
          size="sm"
          :placeholder="t('CRM.SETTINGS.PIPELINES.NAME_PLACEHOLDER')"
        />
      </label>

      <TextArea
        v-model="description"
        :label="t('CRM.SETTINGS.PIPELINES.DESCRIPTION_LABEL')"
        :placeholder="t('CRM.SETTINGS.PIPELINES.DESCRIPTION_PLACEHOLDER')"
      />

      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <p class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('CRM.SETTINGS.PIPELINES.IS_DEFAULT') }}
          </p>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('CRM.SETTINGS.PIPELINES.IS_DEFAULT_HINT') }}
          </p>
        </div>
        <Switch v-model="isDefault" />
      </div>

      <section class="flex flex-col gap-3 pt-2 border-t border-n-weak">
        <div>
          <p class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('CRM.SETTINGS.PIPELINES.INGESTION') }}
          </p>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('CRM.SETTINGS.PIPELINES.INGESTION_HINT') }}
          </p>
        </div>

        <div
          class="flex items-start gap-2 px-3 py-2 rounded-lg"
          :class="
            isIngestionEnabled
              ? 'bg-n-amber-9/10 text-n-amber-11'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
        >
          <Icon
            :icon="
              isIngestionEnabled
                ? 'i-lucide-triangle-alert'
                : 'i-lucide-circle-pause'
            "
            class="flex-shrink-0 mt-0.5 size-4"
          />
          <span class="text-xs">
            {{
              isIngestionEnabled
                ? t('CRM.SETTINGS.PIPELINES.INGESTION_ON_WARNING')
                : t('CRM.SETTINGS.PIPELINES.INGESTION_OFF_HINT')
            }}
          </span>
        </div>

        <ul class="flex flex-col gap-1 overflow-y-auto max-h-48">
          <li v-for="inbox in inboxes" :key="inbox.id">
            <label
              class="flex items-center gap-2 px-2 py-1.5 rounded-md cursor-pointer hover:bg-n-alpha-1"
            >
              <Checkbox
                :model-value="inboxIds.includes(inbox.id)"
                @change="toggleInbox(inbox.id)"
              />
              <span class="text-sm truncate text-n-slate-12">
                {{ inbox.name }}
              </span>
            </label>
          </li>
        </ul>
        <p v-if="!inboxes.length" class="mb-0 text-xs text-n-slate-10">
          {{ t('CRM.SETTINGS.PIPELINES.NO_INBOXES') }}
        </p>

        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CRM.SETTINGS.PIPELINES.DEDUPE_DAYS') }}
          </span>
          <Input v-model="dedupeDays" type="number" size="sm" min="1" />
          <span class="text-xs text-n-slate-10">
            {{ t('CRM.SETTINGS.PIPELINES.DEDUPE_DAYS_HINT') }}
          </span>
        </label>
      </section>

      <section class="flex flex-col gap-4 pt-2 border-t border-n-weak">
        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CRM.SETTINGS.PIPELINES.CURRENCY') }}
          </span>
          <Input v-model="currency" size="sm" placeholder="BRL" />
        </label>

        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <p class="mb-0 text-sm font-medium text-n-slate-12">
              {{ t('CRM.SETTINGS.PIPELINES.REQUIRES_NEXT_ACTIVITY') }}
            </p>
            <p class="mb-0 text-xs text-n-slate-11">
              {{ t('CRM.SETTINGS.PIPELINES.REQUIRES_NEXT_ACTIVITY_HINT') }}
            </p>
          </div>
          <Switch v-model="requiresNextActivity" />
        </div>

        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <p class="mb-0 text-sm font-medium text-n-slate-12">
              {{ t('CRM.SETTINGS.PIPELINES.RESTRICTED_BY_OWNER') }}
            </p>
            <p class="mb-0 text-xs text-n-slate-11">
              {{ t('CRM.SETTINGS.PIPELINES.RESTRICTED_BY_OWNER_HINT') }}
            </p>
          </div>
          <Switch v-model="restrictedByOwner" />
        </div>
      </section>
    </div>
  </Dialog>
</template>
