<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useCrmBoardStore } from 'dashboard/store/crm/board';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const { t } = useI18n();
const store = useCrmBoardStore();

const dialogRef = ref(null);
const selectedReasonId = ref('');

const isPending = computed(() => !!store.getPendingLostReasonMove);

const reasonOptions = computed(() =>
  store.getLostReasons.map(reason => ({
    value: reason.id,
    label: reason.name,
  }))
);

// The store is the single source of truth for the paused move: the modal simply mirrors it, so
// confirming or cancelling from anywhere keeps the dialog in sync.
watch(isPending, pending => {
  selectedReasonId.value = '';
  if (pending) dialogRef.value?.open();
  else dialogRef.value?.close();
});

const handleConfirm = () => store.confirmLostReason(selectedReasonId.value);

const handleClose = () => {
  if (isPending.value) store.cancelLostReasonMove();
};
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="sm"
    :title="t('CRM.LOST_REASON.MODAL_TITLE')"
    :confirm-button-label="t('CRM.LOST_REASON.CONFIRM')"
    :cancel-button-label="t('CRM.LOST_REASON.CANCEL')"
    :disable-confirm-button="!selectedReasonId"
    @confirm="handleConfirm"
    @close="handleClose"
  >
    <Select
      v-model="selectedReasonId"
      class="!w-full [&>select]:w-full"
      :placeholder="t('CRM.LOST_REASON.SELECT')"
      :options="reasonOptions"
    />
  </Dialog>
</template>
