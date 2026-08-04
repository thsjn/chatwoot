<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useCrmBoardStore } from 'dashboard/store/crm/board';

import ListAttribute from 'dashboard/components-next/CustomAttributes/ListAttribute.vue';
import CheckboxAttribute from 'dashboard/components-next/CustomAttributes/CheckboxAttribute.vue';
import DateAttribute from 'dashboard/components-next/CustomAttributes/DateAttribute.vue';
import OtherAttribute from 'dashboard/components-next/CustomAttributes/OtherAttribute.vue';

const props = defineProps({
  deal: { type: Object, required: true },
});

// `text`, `link` and `number` all share the same inline input editor, so they fall through to
// `OtherAttribute` exactly like the contact sidebar does.
const ATTRIBUTE_COMPONENTS = {
  list: ListAttribute,
  checkbox: CheckboxAttribute,
  date: DateAttribute,
};

const { t } = useI18n();
const boardStore = useCrmBoardStore();

const definitions = useMapGetter('attributes/getDealAttributes');

const customAttributes = computed(() => props.deal.custom_attributes || {});

const attributes = computed(() =>
  definitions.value.map(definition => ({
    ...definition,
    value: customAttributes.value[definition.attributeKey] ?? '',
  }))
);

const componentFor = attribute =>
  ATTRIBUTE_COMPONENTS[attribute.attributeDisplayType] || OtherAttribute;

// `custom_attributes` is a single jsonb column, so an update replaces the whole map: every write
// sends the merged object and a delete is the same call with the key dropped.
const save = async nextAttributes => {
  try {
    await boardStore.updateDeal(props.deal.id, {
      custom_attributes: nextAttributes,
    });
  } catch (error) {
    useAlert(t('CRM.DEAL.UPDATE_ERROR'));
  }
};

const handleUpdate = (attribute, value) =>
  save({ ...customAttributes.value, [attribute.attributeKey]: value });

const handleDelete = attribute => {
  const nextAttributes = { ...customAttributes.value };
  delete nextAttributes[attribute.attributeKey];

  return save(nextAttributes);
};
</script>

<template>
  <section v-if="attributes.length" class="flex flex-col gap-2">
    <h3 class="mb-0 text-sm font-medium text-n-slate-12">
      {{ t('CRM.DEAL.CUSTOM_ATTRIBUTES') }}
    </h3>

    <div
      v-for="attribute in attributes"
      :key="attribute.id"
      class="grid min-h-10 w-full grid-cols-[140px,1fr] items-center gap-2 group/attribute"
    >
      <span class="truncate text-sm font-medium text-n-slate-11">
        {{ attribute.attributeDisplayName }}
      </span>
      <component
        :is="componentFor(attribute)"
        :attribute="attribute"
        is-editing-view
        @update="handleUpdate(attribute, $event)"
        @delete="handleDelete(attribute)"
      />
    </div>
  </section>
</template>
