<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useLocale } from 'shared/composables/useLocale';
import { useCrmBoardStore } from 'dashboard/store/crm/board';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  deal: { type: Object, required: true },
  // `rotting_days` belongs to the stage the card currently sits on, so it is passed down
  // instead of read from the deal.
  rottingDays: { type: Number, default: null },
});

const { t } = useI18n();
const { resolvedLocale } = useLocale();
const boardStore = useCrmBoardStore();

const DEFAULT_CURRENCY = 'BRL';

const SECONDS_IN_A_DAY = 86400;

const daysInStage = computed(() => {
  if (!props.deal.stage_entered_at) return 0;

  return Math.floor(
    (Date.now() / 1000 - props.deal.stage_entered_at) / SECONDS_IN_A_DAY
  );
});

// Amber once the card sits past the stage's rotting window, ruby once it doubles it.
const rottingLevel = computed(() => {
  if (!props.rottingDays) return null;
  if (daysInStage.value >= props.rottingDays * 2) return 'danger';
  if (daysInStage.value >= props.rottingDays) return 'warning';

  return null;
});

const rottingClass = computed(() =>
  rottingLevel.value === 'danger'
    ? 'bg-n-ruby-3 text-n-ruby-11'
    : 'bg-n-amber-3 text-n-amber-11'
);

// Realtime pushes merge the websocket payload over the existing card (see
// `applyRealtimeDeal` in the board store) and may omit `currency`, so the pipeline's
// currency stands in first, same fallback `BoardColumn` uses for its totals.
const formattedValue = computed(() =>
  new Intl.NumberFormat(resolvedLocale.value, {
    style: 'currency',
    currency:
      props.deal.currency ||
      boardStore.getSelectedPipeline?.settings?.moeda_padrao ||
      DEFAULT_CURRENCY,
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format((props.deal.value_cents || 0) / 100)
);

// Funnel hygiene: an open deal with no scheduled future task is a deal nobody is working on.
// The board flags it discreetly so it does not compete with the rotting badge.
const isMissingNextActivity = computed(
  () => props.deal.status === 'open' && !props.deal.next_activity_at
);

const formattedExpectedClose = computed(() =>
  new Intl.DateTimeFormat(resolvedLocale.value, {
    day: '2-digit',
    month: 'short',
  }).format(new Date(`${props.deal.expected_close_on}T00:00:00`))
);
</script>

<template>
  <div
    class="flex flex-col gap-2 p-3 transition-colors border rounded-lg shadow-sm cursor-grab bg-n-solid-1 border-n-weak hover:border-n-slate-6 active:cursor-grabbing"
  >
    <div class="flex items-start justify-between gap-2">
      <span class="text-sm font-medium line-clamp-2 text-n-slate-12">
        {{ deal.title }}
      </span>
      <span
        v-if="rottingLevel"
        class="flex-shrink-0 px-1.5 py-0.5 text-xs font-medium rounded-md"
        :class="rottingClass"
      >
        {{ t('CRM.DEAL.ROTTING', { days: daysInStage }) }}
      </span>
    </div>

    <span class="text-sm font-medium tabular-nums text-n-slate-12">
      {{ formattedValue }}
    </span>

    <div class="flex items-center justify-between gap-2">
      <div class="flex items-center min-w-0 gap-1.5">
        <Icon
          icon="i-lucide-user"
          class="flex-shrink-0 size-3.5 text-n-slate-10"
        />
        <span class="text-xs truncate text-n-slate-11">
          {{ deal.contact.name }}
        </span>
      </div>
      <Avatar
        v-if="deal.owner"
        :name="deal.owner.name"
        :src="deal.owner.thumbnail"
        :size="20"
        rounded-full
      />
    </div>

    <div
      v-if="deal.expected_close_on || isMissingNextActivity"
      class="flex items-center gap-3"
    >
      <div
        v-if="deal.expected_close_on"
        class="flex items-center gap-1.5"
        :title="t('CRM.DEAL.EXPECTED_CLOSE')"
      >
        <Icon
          icon="i-lucide-calendar"
          class="flex-shrink-0 size-3.5 text-n-slate-10"
        />
        <span class="text-xs text-n-slate-11">{{ formattedExpectedClose }}</span>
      </div>

      <div
        v-if="isMissingNextActivity"
        class="flex items-center gap-1.5"
        :title="t('CRM.DEAL.NO_NEXT_ACTIVITY')"
      >
        <Icon
          icon="i-lucide-calendar-off"
          class="flex-shrink-0 size-3.5 text-n-amber-11"
        />
        <span class="sr-only">{{ t('CRM.DEAL.NO_NEXT_ACTIVITY') }}</span>
      </div>
    </div>
  </div>
</template>
