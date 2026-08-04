<script setup>
// The board lives under `routes/dashboard/crm`; this file only forwards the legacy
// `kanban_view` entry (still used by the sidebar) so upstream can keep editing it freely.
import { useRouter } from 'vue-router';

const router = useRouter();
router.replace({
  name: 'crm_board',
  params: router.currentRoute.value.params,
});
</script>

<template>
  <span />
</template>
