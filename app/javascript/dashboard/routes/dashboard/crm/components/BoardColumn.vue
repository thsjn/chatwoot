<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';

import { useCrmBoardStore } from 'dashboard/store/crm/board';
import { useLocale } from 'shared/composables/useLocale';

import Button from 'dashboard/components-next/button/Button.vue';
import DealCard from './DealCard.vue';

const props = defineProps({
  stage: { type: Object, required: true },
});

// `stage.color` is a closed token set, so the classes are written as literals for the Tailwind
// scanner to pick them up — an interpolated class name would never be emitted.
const STAGE_ACCENT_CLASSES = {
  slate: 'bg-n-slate-9',
  blue: 'bg-n-blue-9',
  emerald: 'bg-n-teal-9',
  amber: 'bg-n-amber-9',
  ruby: 'bg-n-ruby-9',
  violet: 'bg-n-violet-9',
};

const DEFAULT_CURRENCY = 'BRL';

const { t } = useI18n();
const { resolvedLocale } = useLocale();
const store = useCrmBoardStore();

const deals = computed(() => store.getDealsByStage(props.stage.id));
const stageMeta = computed(() => store.getStageMeta(props.stage.id));
const hasMoreDeals = computed(() => store.hasMoreDeals(props.stage.id));

const accentClass = computed(() => STAGE_ACCENT_CLASSES[props.stage.color]);

// The board only holds the pages it has loaded, so the limit is checked against the stage total
// the server reports — otherwise the alert only lights up after someone loads more cards.
const isWipFull = computed(
  () =>
    !!props.stage.wip_limit && props.stage.deals_count >= props.stage.wip_limit
);

// The total is the whole stage, not the loaded pages, and every deal carries its own currency,
// so it is formatted with the pipeline currency instead of whichever card happens to be first.
const formattedTotal = computed(() =>
  new Intl.NumberFormat(resolvedLocale.value, {
    style: 'currency',
    currency:
      store.getSelectedPipeline?.settings?.moeda_padrao || DEFAULT_CURRENCY,
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format((props.stage.deals_value_cents || 0) / 100)
);

/**
 * `added` fires on the destination column and `moved` on a same-column reorder — both carry the
 * index the card landed on, which is exactly the `targetIndex` the store expects. `removed`
 * (fired on the source column) is ignored: the destination's `added` already describes the move.
 */
const handleChange = event => {
  const change = event.added || event.moved;
  if (!change) return;

  store.moveDeal({
    dealId: change.element.id,
    stageId: props.stage.id,
    targetIndex: change.newIndex,
  });
};
</script>

<template>
  <section
    class="flex flex-col flex-shrink-0 w-80 max-h-full border rounded-xl bg-n-solid-1 border-n-weak"
  >
    <header class="flex flex-col gap-1 px-3 py-3 border-b border-n-weak">
      <div class="flex items-center justify-between gap-2">
        <div class="flex items-center min-w-0 gap-2">
          <span
            v-if="accentClass"
            class="flex-shrink-0 rounded-full size-2"
            :class="accentClass"
          />
          <span class="text-sm font-medium truncate text-n-slate-12">
            {{ stage.name }}
          </span>
        </div>
        <span
          class="flex-shrink-0 px-1.5 py-0.5 text-xs font-medium rounded-md tabular-nums"
          :class="
            isWipFull
              ? 'bg-n-amber-3 text-n-amber-11'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
        >
          {{
            stage.wip_limit
              ? t('CRM.STAGE.WIP_COUNT', {
                  count: stage.deals_count,
                  limit: stage.wip_limit,
                })
              : stage.deals_count
          }}
        </span>
      </div>
      <div class="flex items-center justify-between gap-2">
        <span class="text-xs tabular-nums text-n-slate-11">
          {{ formattedTotal }}
        </span>
        <span v-if="isWipFull" class="text-xs font-medium text-n-amber-11">
          {{ t('CRM.STAGE.WIP_FULL') }}
        </span>
      </div>
    </header>

    <div class="flex flex-col flex-1 min-h-0 overflow-y-auto">
      <Draggable
        :model-value="deals"
        item-key="id"
        :group="{ name: 'crmDeals' }"
        ghost-class="opacity-40"
        class="flex flex-col gap-2 p-2 min-h-[5rem]"
        @change="handleChange"
      >
        <template #item="{ element }">
          <DealCard :deal="element" :rotting-days="stage.rotting_days" />
        </template>
      </Draggable>

      <p
        v-if="!deals.length"
        class="px-3 pb-3 text-xs text-center text-n-slate-10"
      >
        {{ t('CRM.STAGE.EMPTY') }}
      </p>

      <Button
        v-if="hasMoreDeals"
        variant="link"
        color="slate"
        size="sm"
        class="mx-2 mb-2"
        :label="t('CRM.BOARD.LOAD_MORE')"
        :is-loading="stageMeta.isFetching"
        @click="store.loadMoreDeals(stage.id)"
      />
    </div>
  </section>
</template>
