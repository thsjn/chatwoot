<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useCrmSettingsStore } from 'dashboard/store/crm/settings';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Code from 'dashboard/components/Code.vue';

const { t } = useI18n();
const settingsStore = useCrmSettingsStore();

const dialogRef = ref(null);
const source = ref(null);
const token = ref('');
const ingestionUrl = ref('');
const isGenerating = ref(false);

const hasToken = computed(() => !!source.value?.has_token);

/**
 * The request the integrator has to reproduce. It carries the token that was just minted because
 * this is the only screen that will ever hold it — copying the snippet is copying the credential.
 */
const usageSnippet = computed(
  () => `curl -X POST '${ingestionUrl.value}' \\
  -H 'Content-Type: application/json' \\
  -H 'X-Crm-Source-Token: ${token.value}' \\
  -d '{
    "name": "Maria Souza",
    "email": "maria@exemplo.com",
    "phone_number": "+5533999999999",
    "title": "Lote de 30 novilhas",
    "value": 45000.0,
    "utm": { "utm_source": "google", "utm_campaign": "verao" }
  }'`
);

const generate = async () => {
  isGenerating.value = true;
  try {
    const result = await settingsStore.regenerateSourceToken(source.value.id);
    token.value = result.token;
    ingestionUrl.value = result.ingestionUrl;
    source.value = { ...source.value, has_token: true };
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        t('CRM.SETTINGS.SOURCES.TOKEN.GENERATE_ERROR')
    );
  } finally {
    isGenerating.value = false;
  }
};

const open = record => {
  source.value = record;
  // A token from a previous visit is unrecoverable, so the panel always opens empty and only
  // fills in when a NEW one is minted.
  token.value = '';
  ingestionUrl.value = '';
  dialogRef.value?.open();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="xl"
    overflow-y-auto
    :title="t('CRM.SETTINGS.SOURCES.TOKEN.TITLE')"
    :description="t('CRM.SETTINGS.SOURCES.TOKEN.DESCRIPTION')"
    :show-confirm-button="false"
    :cancel-button-label="t('CRM.SETTINGS.SOURCES.TOKEN.CLOSE')"
  >
    <div class="flex flex-col gap-4">
      <div
        v-if="!source?.inbox_id"
        class="p-3 rounded-lg bg-n-amber-3 text-n-amber-11"
      >
        <p class="mb-0 text-sm">
          {{ t('CRM.SETTINGS.SOURCES.TOKEN.INBOX_REQUIRED') }}
        </p>
      </div>

      <div v-if="token" class="flex flex-col gap-2">
        <div class="p-3 rounded-lg bg-n-ruby-3 text-n-ruby-11">
          <p class="mb-0 text-sm font-medium">
            {{ t('CRM.SETTINGS.SOURCES.TOKEN.SHOWN_ONCE') }}
          </p>
        </div>
        <Code :script="token" lang="plaintext" />
      </div>

      <div v-else class="flex flex-col gap-2">
        <p class="mb-0 text-sm text-n-slate-11">
          {{
            hasToken
              ? t('CRM.SETTINGS.SOURCES.TOKEN.EXISTING_HINT')
              : t('CRM.SETTINGS.SOURCES.TOKEN.EMPTY_HINT')
          }}
        </p>
      </div>

      <div v-if="token" class="flex flex-col gap-2">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CRM.SETTINGS.SOURCES.TOKEN.USAGE') }}
        </span>
        <Code :script="usageSnippet" lang="bash" />
        <span class="text-xs text-n-slate-10">
          {{ t('CRM.SETTINGS.SOURCES.TOKEN.USAGE_HINT') }}
        </span>
      </div>

      <Button
        class="self-start"
        size="sm"
        icon="i-lucide-key-round"
        :label="
          hasToken
            ? t('CRM.SETTINGS.SOURCES.TOKEN.REGENERATE')
            : t('CRM.SETTINGS.SOURCES.TOKEN.GENERATE')
        "
        :is-loading="isGenerating"
        :disabled="isGenerating"
        @click="generate"
      />
    </div>
  </Dialog>
</template>
