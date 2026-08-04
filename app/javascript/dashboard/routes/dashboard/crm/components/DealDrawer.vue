<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useEventListener } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { format, fromUnixTime } from 'date-fns';

import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useCrmBoardStore } from 'dashboard/store/crm/board';
import CrmActivitiesAPI from 'dashboard/api/crm/activities';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ConfirmButton from 'dashboard/components-next/button/ConfirmButton.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import DealCustomAttributes from './DealCustomAttributes.vue';

const props = defineProps({
  dealId: { type: [Number, String], default: null },
  open: { type: Boolean, default: true },
});

const emit = defineEmits(['close']);

// Written as literals so the Tailwind icon plugin picks the classes up while scanning.
const ACTIVITY_ICONS = {
  note: 'i-lucide-sticky-note',
  call: 'i-lucide-phone',
  meeting: 'i-lucide-calendar',
  task: 'i-lucide-circle-check-big',
  whatsapp: 'i-lucide-message-circle',
  system: 'i-lucide-settings',
};

const STATUS_LABELS = {
  open: 'CRM.DEAL.STATUS_OPEN',
  won: 'CRM.DEAL.STATUS_WON',
  lost: 'CRM.DEAL.STATUS_LOST',
};

const STATUS_CLASSES = {
  open: 'bg-n-blue-9/10 text-n-blue-11',
  won: 'bg-n-teal-9/10 text-n-teal-11',
  lost: 'bg-n-ruby-9/10 text-n-ruby-11',
};

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const boardStore = useCrmBoardStore();

const agents = useMapGetter('agents/getAgents');
const teams = useMapGetter('teams/getTeams');

const drawerRef = ref(null);

const activities = ref([]);
const isFetchingActivities = ref(false);
const isSavingActivity = ref(false);
const isArchiving = ref(false);
const isUnarchiving = ref(false);

const isEditingTitle = ref(false);
const titleDraft = ref('');
const valueDraft = ref(0);
const expectedCloseDraft = ref('');

const noteDraft = ref('');
const taskDraft = ref('');
const taskDueAt = ref('');

let previousActiveElement = null;

const deal = computed(() => boardStore.getDeal(props.dealId));
const stage = computed(
  () =>
    boardStore.getStages.find(item => item.id === deal.value?.stage_id) || null
);

const isArchived = computed(() => Boolean(deal.value?.archived_at));

const dealValue = computed(() => {
  const currentDeal = deal.value;
  if (!currentDeal) return '';

  return new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency: currentDeal.currency || 'USD',
  }).format((currentDeal.value_cents || 0) / 100);
});

const ownerOptions = computed(() => [
  { value: '', label: t('CRM.DEAL.NO_OWNER') },
  ...agents.value.map(agent => ({
    value: agent.id,
    label: agent.available_name || agent.name,
  })),
]);

const teamOptions = computed(() => [
  { value: '', label: t('CRM.DEAL.NO_TEAM') },
  ...teams.value.map(team => ({ value: team.id, label: team.name })),
]);

const sourceOptions = computed(() => [
  { value: '', label: t('CRM.DEAL.NO_SOURCE') },
  ...boardStore.getSources.map(source => ({
    value: source.id,
    label: source.name,
  })),
]);

const conversations = computed(() => deal.value?.conversations || []);
const hasConversations = computed(() => conversations.value.length > 0);

const conversationRoute = conversation => ({
  name: 'inbox_conversation',
  params: {
    accountId: route.params.accountId,
    conversation_id: conversation.display_id,
  },
});

const sortedActivities = computed(() =>
  [...activities.value].sort((a, b) => a.created_at - b.created_at)
);

const isOverdue = activity =>
  Boolean(activity.due_at) &&
  !activity.completed_at &&
  activity.due_at * 1000 < Date.now();

// The funnel hygiene rule: an open deal without a scheduled future task is a deal nobody is
// working on, so the drawer says it out loud. The deal already carries the aggregate, so the
// warning does not wait on the timeline request.
const isMissingNextActivity = computed(
  () => deal.value?.status === 'open' && !deal.value?.next_activity_at
);

const formatTimestamp = timestamp =>
  timestamp ? format(fromUnixTime(timestamp), 'dd MMM yyyy, HH:mm') : '';

const restoreFocus = () => {
  if (previousActiveElement?.isConnected) previousActiveElement.focus();
  previousActiveElement = null;
};

const closeDrawer = () => {
  emit('close');
  restoreFocus();
};

const fetchActivities = async () => {
  if (!props.dealId) return;

  isFetchingActivities.value = true;
  try {
    const { data } = await CrmActivitiesAPI.getActivities(props.dealId);
    activities.value = data.payload;
  } catch (error) {
    useAlert(t('CRM.ACTIVITY.LOAD_ERROR'));
  } finally {
    isFetchingActivities.value = false;
  }
};

const saveField = async payload => {
  try {
    await boardStore.updateDeal(deal.value.id, payload);
  } catch (error) {
    useAlert(t('CRM.DEAL.UPDATE_ERROR'));
  }
};

const startTitleEdit = () => {
  titleDraft.value = deal.value?.title || '';
  isEditingTitle.value = true;
};

const cancelTitleEdit = () => {
  isEditingTitle.value = false;
};

// Enter closes the editor and blur fires right after it, so the flag is what keeps the same
// title from being submitted twice.
const submitTitle = async () => {
  if (!isEditingTitle.value) return;

  const title = titleDraft.value.trim();
  isEditingTitle.value = false;
  if (!title || title === deal.value?.title) return;

  await saveField({ title });
};

const submitValue = async () => {
  const valueCents = Math.round(Number(valueDraft.value) * 100);
  if (valueCents === deal.value.value_cents) return;

  await saveField({ value_cents: valueCents });
};

const submitExpectedCloseOn = async () => {
  const expectedCloseOn = expectedCloseDraft.value || null;
  if (expectedCloseOn === (deal.value.expected_close_on || null)) return;

  await saveField({ expected_close_on: expectedCloseOn });
};

const updateOwner = async value => {
  await saveField({ owner_id: value === '' ? null : value });
};

const updateTeam = async value => {
  await saveField({ team_id: value === '' ? null : value });
};

const updateSource = async value => {
  await saveField({ source_id: value === '' ? null : value });
};

const archive = async () => {
  isArchiving.value = true;
  try {
    await boardStore.archiveDeal(deal.value.id);
    useAlert(t('CRM.DEAL.ARCHIVE_SUCCESS'));
    closeDrawer();
  } catch (error) {
    useAlert(t('CRM.DEAL.ARCHIVE_ERROR'));
  } finally {
    isArchiving.value = false;
  }
};

// Restoring is not destructive — the card simply goes back to its column — so it skips the
// confirmation step that archiving needs.
const unarchive = async () => {
  const dealId = deal.value.id;
  isUnarchiving.value = true;
  try {
    await boardStore.unarchiveDeal(dealId);
    useAlert(t('CRM.DEAL.UNARCHIVE_SUCCESS'));
    closeDrawer();
  } catch (error) {
    useAlert(t('CRM.DEAL.UNARCHIVE_ERROR'));
  } finally {
    isUnarchiving.value = false;
  }
};

const createActivity = async payload => {
  isSavingActivity.value = true;
  try {
    const { data } = await CrmActivitiesAPI.createActivity(
      deal.value.id,
      payload
    );
    activities.value = [...activities.value, data];
  } catch (error) {
    useAlert(t('CRM.ACTIVITY.CREATE_ERROR'));
  } finally {
    isSavingActivity.value = false;
  }
};

const submitNote = async () => {
  const content = noteDraft.value.trim();
  if (!content) return;

  await createActivity({ kind: 'note', content });
  noteDraft.value = '';
};

const submitTask = async () => {
  const content = taskDraft.value.trim();
  if (!content || !taskDueAt.value) return;

  await createActivity({
    kind: 'task',
    content,
    due_at: new Date(taskDueAt.value).toISOString(),
  });
  taskDraft.value = '';
  taskDueAt.value = '';
};

const completeActivity = async activity => {
  try {
    const { data } = await CrmActivitiesAPI.updateActivity(
      deal.value.id,
      activity.id,
      { completed_at: new Date().toISOString() }
    );
    activities.value = activities.value.map(item =>
      item.id === data.id ? data : item
    );
  } catch (error) {
    useAlert(t('CRM.ACTIVITY.UPDATE_ERROR'));
  }
};

const onKeydown = event => {
  if (!props.open || event.key !== 'Escape') return;

  event.preventDefault();
  event.stopPropagation();
  closeDrawer();
};

useEventListener(document, 'keydown', onKeydown);

watch(
  deal,
  currentDeal => {
    if (!currentDeal) return;

    valueDraft.value = (currentDeal.value_cents || 0) / 100;
    expectedCloseDraft.value = currentDeal.expected_close_on || '';
  },
  { immediate: true }
);

watch(
  () => [props.open, props.dealId],
  ([isOpen]) => {
    if (!isOpen) {
      restoreFocus();
      return;
    }

    previousActiveElement =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null;
    isEditingTitle.value = false;
    fetchActivities();
    nextTick(() => drawerRef.value?.focus());
  },
  { immediate: true }
);

onMounted(() => {
  store.dispatch('agents/get');
  store.dispatch('teams/get');
  store.dispatch('attributes/get');
});
</script>

<template>
  <TeleportWithDirection to="body">
    <div
      v-if="open && deal"
      class="fixed inset-0 z-50 bg-black/30"
      role="presentation"
      @click.self="closeDrawer"
    >
      <aside
        ref="drawerRef"
        class="fixed inset-y-0 end-0 flex w-full max-w-2xl flex-col bg-n-solid-1 shadow-xl outline outline-1 outline-n-container"
        role="dialog"
        aria-modal="true"
        :aria-label="deal.title"
        tabindex="-1"
      >
        <header
          class="flex items-start justify-between gap-4 border-b border-n-weak px-6 py-5"
        >
          <div class="min-w-0 flex-1">
            <div v-if="isEditingTitle" class="flex items-center gap-2">
              <Input
                v-model="titleDraft"
                autofocus
                size="sm"
                class="flex-1"
                :placeholder="$t('CRM.DEAL.TITLE_PLACEHOLDER')"
                @enter="submitTitle"
                @blur="submitTitle"
              />
              <Button
                ghost
                slate
                size="sm"
                icon="i-lucide-x"
                :aria-label="$t('CRM.DEAL.CANCEL')"
                @mousedown.prevent="cancelTitleEdit"
              />
            </div>
            <button
              v-else
              type="button"
              class="group flex w-full items-center gap-2 rounded-md text-start"
              :aria-label="$t('CRM.DEAL.EDIT_TITLE')"
              @click="startTitleEdit"
            >
              <span class="truncate text-base font-medium text-n-slate-12">
                {{ deal.title }}
              </span>
              <span
                class="i-lucide-pencil size-3.5 shrink-0 text-n-slate-10 opacity-0 transition-opacity group-hover:opacity-100"
              />
            </button>

            <div class="mt-2 flex flex-wrap items-center gap-2">
              <span class="text-xl font-semibold text-n-slate-12">
                {{ dealValue }}
              </span>
              <span
                v-if="stage"
                class="rounded-md bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
              >
                {{ stage.name }}
              </span>
              <span
                class="rounded-md px-2 py-0.5 text-xs font-medium"
                :class="STATUS_CLASSES[deal.status]"
              >
                {{ $t(STATUS_LABELS[deal.status]) }}
              </span>
              <span
                v-if="isArchived"
                class="flex items-center gap-1 rounded-md bg-n-amber-9/10 px-2 py-0.5 text-xs font-medium text-n-amber-11"
              >
                <span class="i-lucide-archive size-3" />
                {{ $t('CRM.DEAL.ARCHIVED_BADGE') }}
              </span>
            </div>
          </div>

          <div class="flex shrink-0 items-center gap-2">
            <Button
              v-if="isArchived"
              faded
              teal
              size="sm"
              icon="i-lucide-archive-restore"
              :label="$t('CRM.DEAL.UNARCHIVE')"
              :is-loading="isUnarchiving"
              @click="unarchive"
            />
            <ConfirmButton
              v-else
              slate
              variant="faded"
              size="sm"
              icon="i-lucide-archive"
              :label="$t('CRM.DEAL.ARCHIVE')"
              :confirm-label="$t('CRM.DEAL.ARCHIVE_CONFIRM')"
              :confirm-hint="$t('CRM.DEAL.ARCHIVE_HINT')"
              :is-loading="isArchiving"
              @click="archive"
            />
            <Button
              ghost
              slate
              size="sm"
              icon="i-lucide-x"
              :aria-label="$t('CRM.DEAL.CLOSE')"
              @click="closeDrawer"
            />
          </div>
        </header>

        <div
          class="flex min-h-0 flex-1 flex-col gap-6 overflow-y-auto px-6 py-5"
        >
          <div
            v-if="isMissingNextActivity"
            class="flex items-start gap-3 rounded-xl bg-n-amber-9/10 px-4 py-3 outline outline-1 outline-n-amber-9/40"
          >
            <span
              class="i-lucide-triangle-alert mt-0.5 size-5 shrink-0 text-n-amber-11"
            />
            <div class="min-w-0">
              <p class="mb-0 text-sm font-medium text-n-slate-12">
                {{ $t('CRM.DEAL.NO_NEXT_ACTIVITY') }}
              </p>
              <p class="mb-0 mt-0.5 text-sm text-n-slate-11">
                {{ $t('CRM.DEAL.NEXT_ACTIVITY_HINT') }}
              </p>
            </div>
          </div>

          <section class="flex flex-col gap-4">
            <h3 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ $t('CRM.DEAL.DETAILS') }}
            </h3>

            <div
              class="flex items-center gap-3 rounded-xl bg-n-solid-2 px-4 py-3"
            >
              <Avatar
                :name="deal.contact.name"
                :src="deal.contact.thumbnail"
                :size="36"
                rounded-full
              />
              <div class="min-w-0">
                <p class="mb-0 truncate text-sm font-medium text-n-slate-12">
                  {{ deal.contact.name }}
                </p>
                <p class="mb-0 truncate text-xs text-n-slate-11">
                  {{ deal.contact.phone_number || $t('CRM.DEAL.NO_PHONE') }}
                  ⋅
                  {{ deal.contact.email || $t('CRM.DEAL.NO_EMAIL') }}
                </p>
              </div>
            </div>

            <div class="grid grid-cols-2 gap-4">
              <label class="flex flex-col gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ $t('CRM.DEAL.OWNER') }}
                </span>
                <Select
                  class="!w-full [&_select]:w-full"
                  :model-value="deal.owner?.id || ''"
                  :options="ownerOptions"
                  @update:model-value="updateOwner"
                />
              </label>

              <label class="flex flex-col gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ $t('CRM.DEAL.TEAM') }}
                </span>
                <Select
                  class="!w-full [&_select]:w-full"
                  :model-value="deal.team?.id || ''"
                  :options="teamOptions"
                  @update:model-value="updateTeam"
                />
              </label>

              <label class="flex flex-col gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ $t('CRM.DEAL.SOURCE') }}
                </span>
                <Select
                  class="!w-full [&_select]:w-full"
                  :model-value="deal.source?.id || ''"
                  :options="sourceOptions"
                  @update:model-value="updateSource"
                />
              </label>

              <label class="flex flex-col gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ $t('CRM.DEAL.EXPECTED_CLOSE') }}
                </span>
                <Input
                  v-model="expectedCloseDraft"
                  type="date"
                  size="sm"
                  @blur="submitExpectedCloseOn"
                />
              </label>

              <label class="flex flex-col gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ $t('CRM.DEAL.VALUE') }}
                </span>
                <Input
                  v-model="valueDraft"
                  type="number"
                  size="sm"
                  @blur="submitValue"
                  @enter="submitValue"
                />
              </label>

              <div class="flex flex-col gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ $t('CRM.DEAL.CREATED_AT') }}
                </span>
                <p class="mb-0 py-2 text-sm text-n-slate-12">
                  {{ formatTimestamp(deal.created_at) }}
                </p>
              </div>
            </div>
          </section>

          <DealCustomAttributes :deal="deal" />

          <section class="flex flex-col gap-2">
            <h3 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ $t('CRM.DEAL.CONVERSATIONS') }}
            </h3>
            <ul v-if="hasConversations" class="flex flex-col gap-2">
              <li v-for="conversation in conversations" :key="conversation.id">
                <router-link
                  :to="conversationRoute(conversation)"
                  class="flex items-center gap-2 rounded-lg bg-n-solid-2 px-3 py-2 hover:bg-n-alpha-2"
                >
                  <span
                    class="i-lucide-message-circle size-4 shrink-0 text-n-slate-11"
                  />
                  <span class="shrink-0 text-sm font-medium text-n-slate-12">
                    {{
                      $t('CRM.DEAL.CONVERSATION_ID', {
                        id: conversation.display_id,
                      })
                    }}
                  </span>
                  <span class="truncate text-xs text-n-slate-11">
                    {{ conversation.inbox.name }}
                  </span>
                  <span
                    v-if="conversation.is_origin"
                    class="ms-auto shrink-0 rounded-md bg-n-blue-9/10 px-2 py-0.5 text-xs font-medium text-n-blue-11"
                  >
                    {{ $t('CRM.DEAL.CONVERSATION_ORIGIN') }}
                  </span>
                </router-link>
              </li>
            </ul>
            <p v-else class="mb-0 text-sm text-n-slate-10">
              {{ $t('CRM.DEAL.NO_CONVERSATIONS') }}
            </p>
          </section>

          <section class="flex flex-col gap-3">
            <h3 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ $t('CRM.ACTIVITY.TIMELINE') }}
            </h3>

            <div class="flex flex-col gap-3 rounded-xl bg-n-solid-2 p-4">
              <TextArea
                v-model="noteDraft"
                :placeholder="$t('CRM.ACTIVITY.NOTE_PLACEHOLDER')"
                :max-length="1000"
                auto-height
              />
              <div class="flex justify-end">
                <Button
                  faded
                  slate
                  size="sm"
                  icon="i-lucide-sticky-note"
                  :label="$t('CRM.ACTIVITY.KIND.NOTE')"
                  :disabled="!noteDraft.trim() || isSavingActivity"
                  @click="submitNote"
                />
              </div>

              <div class="flex flex-col gap-2 border-t border-n-weak pt-3">
                <Input
                  v-model="taskDraft"
                  size="sm"
                  :placeholder="$t('CRM.ACTIVITY.TASK_PLACEHOLDER')"
                />
                <div class="flex items-end gap-2">
                  <Input
                    v-model="taskDueAt"
                    type="datetime-local"
                    size="sm"
                    class="flex-1"
                    :label="$t('CRM.ACTIVITY.DUE_AT')"
                  />
                  <Button
                    slate
                    size="sm"
                    icon="i-lucide-circle-check-big"
                    :label="$t('CRM.ACTIVITY.KIND.TASK')"
                    :disabled="
                      !taskDraft.trim() || !taskDueAt || isSavingActivity
                    "
                    @click="submitTask"
                  />
                </div>
              </div>
            </div>

            <div
              v-if="isFetchingActivities"
              class="flex h-24 items-center justify-center"
            >
              <Spinner />
            </div>

            <p
              v-else-if="!sortedActivities.length"
              class="mb-0 py-4 text-center text-sm text-n-slate-10"
            >
              {{ $t('CRM.ACTIVITY.EMPTY') }}
            </p>

            <ul v-else class="flex flex-col gap-2">
              <li
                v-for="activity in sortedActivities"
                :key="activity.id"
                class="flex items-start gap-3 rounded-xl px-3 py-3 outline outline-1"
                :class="
                  isOverdue(activity)
                    ? 'bg-n-ruby-9/10 outline-n-ruby-9/40'
                    : 'bg-n-solid-2 outline-n-weak'
                "
              >
                <span
                  class="mt-0.5 size-4 shrink-0"
                  :class="[
                    ACTIVITY_ICONS[activity.kind],
                    isOverdue(activity) ? 'text-n-ruby-11' : 'text-n-slate-11',
                  ]"
                />
                <div class="min-w-0 flex-1">
                  <div class="flex flex-wrap items-center gap-2">
                    <span class="text-xs font-medium text-n-slate-11">
                      {{
                        $t(`CRM.ACTIVITY.KIND.${activity.kind.toUpperCase()}`)
                      }}
                    </span>
                    <span class="text-xs text-n-slate-10">
                      {{ formatTimestamp(activity.created_at) }}
                    </span>
                    <span v-if="activity.user" class="text-xs text-n-slate-10">
                      {{ activity.user.name }}
                    </span>
                    <span
                      v-if="isOverdue(activity)"
                      class="rounded bg-n-ruby-9/20 px-1.5 py-0.5 text-xs font-medium text-n-ruby-11"
                    >
                      {{ $t('CRM.ACTIVITY.OVERDUE') }}
                    </span>
                  </div>
                  <p
                    class="mb-0 mt-1 whitespace-pre-line text-sm"
                    :class="
                      activity.completed_at
                        ? 'text-n-slate-10 line-through'
                        : 'text-n-slate-12'
                    "
                  >
                    {{ activity.content }}
                  </p>
                  <p
                    v-if="activity.due_at"
                    class="mb-0 mt-1 text-xs text-n-slate-11"
                  >
                    {{ $t('CRM.ACTIVITY.DUE_AT') }}:
                    {{ formatTimestamp(activity.due_at) }}
                  </p>
                </div>

                <Button
                  v-if="activity.due_at && !activity.completed_at"
                  ghost
                  teal
                  size="xs"
                  icon="i-lucide-check"
                  :aria-label="$t('CRM.ACTIVITY.MARK_DONE')"
                  @click="completeActivity(activity)"
                />
                <span
                  v-else-if="activity.completed_at"
                  class="text-xs text-n-teal-11"
                >
                  {{ $t('CRM.ACTIVITY.COMPLETED') }}
                </span>
              </li>
            </ul>
          </section>
        </div>
      </aside>
    </div>
  </TeleportWithDirection>
</template>
