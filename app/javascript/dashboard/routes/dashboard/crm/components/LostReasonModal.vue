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

// A reason the account retired between the board loading its list and the agent picking it comes
// back as `lost_reason_inactive`. The move stays pending, so the dialog stays open and says why
// the confirmation did not go through.
const warningMessageKey = computed(() => {
  const moveError = store.getMoveError;
  if (!moveError || moveError.code !== 'lost_reason_inactive') return null;

  return moveError.messageKey;
});

// The store is the single source of truth for the paused move: the modal simply mirrors it, so
// confirming or cancelling from anywhere keeps the dialog in sync.
watch(isPending, pending => {
  selectedReasonId.value = '';
  if (pending) dialogRef.value?.open();
  else dialogRef.value?.close();
});

// The rejected reason has just left the list (the store refetches it), so the selection it left
// behind points at nothing and has to be cleared for the confirm button to mean something.
watch(warningMessageKey, key => {
  if (key) selectedReasonId.value = '';
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
    <div class="flex flex-col gap-3">
      <p
        v-if="warningMessageKey"
        class="mb-0 rounded-lg bg-n-amber-9/10 px-3 py-2 text-sm text-n-amber-11"
      >
        {{ t(warningMessageKey) }}
      </p>
      <Select
        v-model="selectedReasonId"
        class="!w-full [&>select]:w-full"
        :placeholder="t('CRM.LOST_REASON.SELECT')"
        :options="reasonOptions"
      />
    </div>
  </Dialog>
</template>
