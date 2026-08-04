<script setup>
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

defineProps({
  title: { type: String, required: true },
  description: { type: String, default: '' },
  hint: { type: String, default: '' },
  isLoading: { type: Boolean, default: false },
  isEmpty: { type: Boolean, default: false },
  emptyLabel: { type: String, required: true },
  highlighted: { type: Boolean, default: false },
});
</script>

<template>
  <section
    class="flex flex-col gap-4 px-6 py-5 shadow rounded-xl bg-n-solid-2 outline outline-1"
    :class="highlighted ? 'outline-n-blue-8' : 'outline-n-container'"
  >
    <header class="flex flex-wrap items-start gap-x-4 gap-y-1">
      <div class="flex flex-col gap-1 min-w-0">
        <h2 class="text-base font-medium text-n-slate-12">{{ title }}</h2>
        <p v-if="description" class="text-sm text-n-slate-11">
          {{ description }}
        </p>
      </div>
      <div class="flex items-center gap-2 ms-auto">
        <slot name="actions" />
      </div>
    </header>

    <p v-if="hint" class="text-xs text-n-amber-11">{{ hint }}</p>

    <div
      v-if="isLoading"
      class="flex items-center justify-center py-10 text-n-slate-11"
    >
      <Spinner :size="20" />
    </div>
    <div
      v-else-if="isEmpty"
      class="flex items-center justify-center py-10 text-sm text-n-slate-10"
    >
      {{ emptyLabel }}
    </div>
    <slot v-else />
  </section>
</template>
