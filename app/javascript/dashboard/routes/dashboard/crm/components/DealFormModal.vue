<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';

import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useCrmBoardStore } from 'dashboard/store/crm/board';
import { createContactSearcher } from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';

import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const emit = defineEmits(['created']);

const SEARCH_DEBOUNCE_MS = 300;
const DEFAULT_CURRENCY = 'BRL';

const { t } = useI18n();
const store = useStore();
const boardStore = useCrmBoardStore();

const agents = useMapGetter('agents/getAgents');

// One searcher per component: it keeps the AbortController of the request in flight, so a fast
// typist cancels their own previous search instead of racing two responses into the list.
const searchContacts = createContactSearcher();

const dialogRef = ref(null);
const isSaving = ref(false);

const contactId = ref('');
const contactName = ref('');
const contactOptions = ref([]);
const title = ref('');
const stageId = ref('');
const value = ref('');
const ownerId = ref('');
const expectedCloseOn = ref('');

const stageOptions = computed(() =>
  boardStore.getStages.map(stage => ({ value: stage.id, label: stage.name }))
);

const ownerOptions = computed(() => [
  { value: '', label: t('CRM.DEAL_FORM.NO_OWNER') },
  ...agents.value.map(agent => ({
    value: agent.id,
    label: agent.available_name || agent.name,
  })),
]);

// A card always belongs to a contact and to a column, so those are the two fields the form
// cannot submit without.
const isInvalid = computed(
  () => !contactId.value || !title.value.trim() || !stageId.value
);

const resetForm = stage => {
  contactId.value = '';
  contactName.value = '';
  contactOptions.value = [];
  title.value = '';
  value.value = '';
  ownerId.value = '';
  expectedCloseOn.value = '';
  stageId.value = stage || boardStore.getStages[0]?.id || '';
};

const fetchContacts = async query => {
  // `reachableOnly` filters out contacts without email or phone, which is what the compose
  // conversation flow needs: a deal only needs someone to attach the card to.
  // `skipMinLength` lets the freshly opened dropdown list something before any typing.
  const results = await searchContacts(query, {
    skipMinLength: true,
    reachableOnly: false,
  });
  // `null` means the request was aborted by a newer one, so the list must keep whatever the
  // still-pending search is about to replace it with.
  if (results === null) return;

  contactOptions.value = (results || []).map(contact => ({
    value: contact.id,
    label: contact.email
      ? `${contact.name} (${contact.email})`
      : contact.name || contact.phoneNumber,
  }));
};

const handleContactSearch = useDebounceFn(
  query => fetchContacts(query?.trim() || ''),
  SEARCH_DEBOUNCE_MS
);

const handleContactSelect = selected => {
  const id = selected ? Number(selected) : '';
  contactId.value = id;
  contactName.value =
    contactOptions.value.find(option => option.value === id)?.label || '';

  // The card is named after whoever it is about until someone renames it — same fallback the
  // automatic ingestion uses, so a manual card reads like the ones the funnel creates itself.
  if (!title.value.trim() && contactName.value)
    title.value = contactName.value.replace(/\s*\(.*\)$/, '');
};

const submit = async () => {
  if (isInvalid.value) return;

  isSaving.value = true;
  try {
    await boardStore.createDeal({
      pipeline_id: boardStore.selectedPipelineId,
      stage_id: stageId.value,
      contact_id: contactId.value,
      title: title.value.trim(),
      value_cents: Math.round(Number(value.value || 0) * 100),
      currency:
        boardStore.getSelectedPipeline?.settings?.moeda_padrao ||
        DEFAULT_CURRENCY,
      ...(ownerId.value ? { owner_id: ownerId.value } : {}),
      ...(expectedCloseOn.value
        ? { expected_close_on: expectedCloseOn.value }
        : {}),
    });
    useAlert(t('CRM.DEAL_FORM.SUCCESS'));
    emit('created');
    dialogRef.value?.close();
  } catch (error) {
    useAlert(t('CRM.DEAL_FORM.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const open = stage => {
  resetForm(stage);
  dialogRef.value?.open();
};

watch(
  () => agents.value.length,
  length => {
    if (!length) store.dispatch('agents/get');
  },
  { immediate: true }
);

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="md"
    :title="t('CRM.DEAL_FORM.TITLE')"
    :confirm-button-label="t('CRM.DEAL_FORM.SUBMIT')"
    :cancel-button-label="t('CRM.DEAL_FORM.CANCEL')"
    :disable-confirm-button="isInvalid"
    :is-loading="isSaving"
    @confirm="submit"
  >
    <div class="flex flex-col gap-4">
      <label class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CRM.DEAL_FORM.CONTACT') }}
        </span>
        <ComboBox
          :model-value="contactId"
          :options="contactOptions"
          :display-label="contactName"
          :placeholder="t('CRM.DEAL_FORM.CONTACT_PLACEHOLDER')"
          :search-placeholder="t('CRM.DEAL_FORM.CONTACT_SEARCH')"
          :empty-state="t('CRM.DEAL_FORM.CONTACT_EMPTY')"
          use-api-results
          @open="fetchContacts('')"
          @search="handleContactSearch"
          @update:model-value="handleContactSelect"
        />
      </label>

      <label class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CRM.DEAL_FORM.DEAL_TITLE') }}
        </span>
        <Input
          v-model="title"
          size="sm"
          :placeholder="t('CRM.DEAL_FORM.DEAL_TITLE_PLACEHOLDER')"
        />
      </label>

      <label class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CRM.DEAL_FORM.STAGE') }}
        </span>
        <Select
          v-model="stageId"
          class="!w-full [&_select]:w-full"
          :options="stageOptions"
          :placeholder="t('CRM.DEAL_FORM.STAGE_PLACEHOLDER')"
        />
      </label>

      <div class="grid grid-cols-2 gap-4">
        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CRM.DEAL_FORM.VALUE') }}
          </span>
          <Input v-model="value" type="number" size="sm" placeholder="0" />
        </label>

        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CRM.DEAL_FORM.EXPECTED_CLOSE') }}
          </span>
          <Input v-model="expectedCloseOn" type="date" size="sm" />
        </label>
      </div>

      <label class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CRM.DEAL_FORM.OWNER') }}
        </span>
        <Select
          v-model="ownerId"
          class="!w-full [&_select]:w-full"
          :options="ownerOptions"
        />
      </label>
    </div>
  </Dialog>
</template>
