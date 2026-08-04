<script setup>
// Legacy `kanban_view` entry — the one the upstream sidebar points at, which is why this file is
// kept as thin as possible (it conflicts on every rebase).
//
// With the account toggle `settings.crm_kanban` on, it forwards to our board, which lives under
// `routes/dashboard/crm`. With it off it renders the upstream fazer.ai paywall, so an account that
// never enabled the module sees exactly what it saw before the CRM shipped.
import { computed, ref, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStoreGetters } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { isCrmModuleEnabled } from '../crm/crmModuleGate';

import Icon from 'dashboard/components-next/icon/Icon.vue';

const UPGRADE_URL = 'https://fazer.ai/kanban';

const router = useRouter();
const { t } = useI18n();
const { accountId } = useAccount();
const getters = useStoreGetters();

const showPaywall = ref(false);

const canUpgrade = computed(
  () =>
    getters.getCurrentRole.value === 'administrator' ||
    getters.getCurrentUser.value?.type === 'SuperAdmin'
);

onMounted(async () => {
  if (await isCrmModuleEnabled(accountId.value)) {
    router.replace({
      name: 'crm_board',
      params: router.currentRoute.value.params,
    });
    return;
  }

  showPaywall.value = true;
});
</script>

<template>
  <div v-if="showPaywall" class="flex items-center justify-center w-full h-full">
    <div
      class="flex flex-col max-w-md gap-3 px-6 py-6 border shadow rounded-xl border-n-weak bg-n-solid-1"
    >
      <div class="flex items-center gap-2">
        <span
          class="flex items-center justify-center rounded-full size-6 bg-n-solid-blue"
        >
          <Icon
            class="flex-shrink-0 text-n-brand size-[14px]"
            icon="i-lucide-lock-keyhole"
          />
        </span>
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.PAYWALL.TITLE') }}
        </span>
      </div>
      <p class="text-sm text-n-slate-11">
        {{ t('KANBAN.PAYWALL.DESCRIPTION') }}
      </p>
      <template v-if="canUpgrade">
        <p class="text-sm text-n-slate-11">
          {{ t('KANBAN.PAYWALL.UPGRADE_PROMPT') }}
        </p>
        <a
          :href="UPGRADE_URL"
          target="_blank"
          rel="noopener noreferrer"
          class="flex items-center justify-center w-full px-3 py-1.5 text-sm font-medium text-white rounded-xl bg-n-brand hover:opacity-90"
        >
          {{ t('KANBAN.PAYWALL.UPGRADE_NOW') }}
        </a>
      </template>
      <p v-else class="text-sm text-n-slate-11">
        {{ t('KANBAN.PAYWALL.NON_ADMIN_MESSAGE') }}
      </p>
    </div>
  </div>
  <span v-else />
</template>
