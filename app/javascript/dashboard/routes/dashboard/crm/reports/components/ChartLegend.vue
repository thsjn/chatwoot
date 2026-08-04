<script setup>
defineProps({
  // [{ label, color }] where `color` is a key of CHART_COLORS.
  items: { type: Array, required: true },
});

// `shared/components/charts/BarChart.vue` only registers the chart.js pieces it
// needs, and Legend is not one of them — registering it here would switch
// legends on for every other report in the dashboard, so the legend is drawn in
// the template instead. The dot classes are literals for the Tailwind scanner.
const DOT_CLASSES = {
  primary: 'bg-n-blue-9',
  muted: 'bg-n-slate-9',
  positive: 'bg-n-teal-9',
  negative: 'bg-n-ruby-9',
};
</script>

<template>
  <div class="flex flex-wrap items-center gap-4">
    <span
      v-for="item in items"
      :key="item.label"
      class="flex items-center gap-2 text-xs text-n-slate-11"
    >
      <span class="rounded-full size-2.5" :class="DOT_CLASSES[item.color]" />
      {{ item.label }}
    </span>
  </div>
</template>
