import { defineStore } from 'pinia';
import CrmPipelinesAPI from 'dashboard/api/crm/pipelines';
import CrmStagesAPI from 'dashboard/api/crm/stages';
import CrmSourcesAPI from 'dashboard/api/crm/sources';
import CrmLostReasonsAPI from 'dashboard/api/crm/lostReasons';

// Mirrors `Crm::Stage::COLORS`. The colour is a design token, never a hex value: the board
// styles the column with Tailwind classes and cannot apply an arbitrary colour.
export const STAGE_COLORS = [
  'slate',
  'blue',
  'emerald',
  'amber',
  'ruby',
  'violet',
];

// Mirrors the `category` enum of `Crm::Stage`.
export const STAGE_CATEGORIES = ['open', 'won', 'lost'];

// Mirrors the `kind` enum of `Crm::Source`.
export const SOURCE_KINDS = [
  'inbox',
  'landing',
  'import',
  'api',
  'n8n',
  'manual',
];

/**
 * The five keys `Crm::Pipeline::SETTINGS_KEYS` expects. `inbox_ids` empty is what keeps the
 * automatic ingestion OFF, which is the shipped default.
 */
export const DEFAULT_PIPELINE_SETTINGS = {
  inbox_ids: [],
  janela_dedupe_dias: 30,
  exige_proxima_atividade: false,
  moeda_padrao: 'BRL',
  restrito_por_owner: false,
};

/**
 * `PipelinesController#update` permits `settings` as a whole hash, and assigning it REPLACES the
 * stored one — a payload carrying only the edited key would wipe the other four. Every write
 * therefore goes through here, which fills the gaps with the defaults.
 *
 * `inbox_ids` is cast to numbers because `Crm::IngestConversationService` matches the jsonb array
 * against the inbox id, and a value stored as a string only matches the string branch of that
 * query — a select bound to string ids would produce a pipeline that silently ingests nothing.
 */
export const buildPipelineSettings = (settings = {}) => ({
  ...DEFAULT_PIPELINE_SETTINGS,
  ...settings,
  inbox_ids: (settings.inbox_ids || []).map(Number),
});

export const useCrmSettingsStore = defineStore('crmSettings', {
  state: () => ({
    pipelines: [],
    // Stages of the pipeline currently being edited, ordered by position.
    stages: [],
    stagesPipelineId: null,
    // Both listings carry the inactive records: this is the administration screen, and the
    // `active` flag is what it exists to manage.
    sources: [],
    lostReasons: [],
    uiFlags: {
      fetchingPipelines: false,
      fetchingStages: false,
      fetchingSources: false,
      fetchingLostReasons: false,
      isSaving: false,
    },
  }),

  getters: {
    getPipelines: state => state.pipelines,
    getStages: state => state.stages,
    getSources: state => state.sources,
    getLostReasons: state => state.lostReasons,
    getUIFlags: state => state.uiFlags,
  },

  actions: {
    // --- pipelines ----------------------------------------------------------------------

    // `include_archived` is what separates this listing from the board one: a retired funnel has to
    // stay visible here to be restored, while the board only ever offers the active ones.
    async fetchPipelines() {
      this.uiFlags.fetchingPipelines = true;
      try {
        const { data } = await CrmPipelinesAPI.get({ include_archived: true });
        this.pipelines = data.payload;
        return this.pipelines;
      } finally {
        this.uiFlags.fetchingPipelines = false;
      }
    },

    async createPipeline(payload) {
      this.uiFlags.isSaving = true;
      try {
        const { data } = await CrmPipelinesAPI.create(payload);
        this.pipelines = [...this.pipelines, data];
        return data;
      } finally {
        this.uiFlags.isSaving = false;
      }
    },

    async updatePipeline(id, payload) {
      this.uiFlags.isSaving = true;
      try {
        const { data } = await CrmPipelinesAPI.update(id, payload);
        this.pipelines = this.pipelines.map(pipeline =>
          pipeline.id === data.id ? data : pipeline
        );
        return data;
      } finally {
        this.uiFlags.isSaving = false;
      }
    },

    /**
     * Archiving is the way to retire a funnel that is in use: `delete` is refused while it holds
     * deals, and the deals themselves are left untouched, so restoring brings the board back.
     *
     * @param {number} id Pipeline to retire.
     * @param {boolean} archived Target state — false restores it.
     */
    async setPipelineArchived(id, archived) {
      this.uiFlags.isSaving = true;
      try {
        const { data } = archived
          ? await CrmPipelinesAPI.archive(id)
          : await CrmPipelinesAPI.unarchive(id);
        this.pipelines = this.pipelines.map(pipeline =>
          pipeline.id === data.id ? data : pipeline
        );
        return data;
      } finally {
        this.uiFlags.isSaving = false;
      }
    },

    // A pipeline still holding deals is refused with a 422 (`restrict_with_error`), so the
    // caller surfaces the message instead of the list losing a row that is still there.
    async deletePipeline(id) {
      await CrmPipelinesAPI.delete(id);
      this.pipelines = this.pipelines.filter(pipeline => pipeline.id !== id);
    },

    // --- stages -------------------------------------------------------------------------

    async fetchStages(pipelineId) {
      this.uiFlags.fetchingStages = true;
      this.stagesPipelineId = Number(pipelineId);
      try {
        const { data } = await CrmStagesAPI.getStages(pipelineId);
        this.stages = data.payload;
        return this.stages;
      } finally {
        this.uiFlags.fetchingStages = false;
      }
    },

    async createStage(pipelineId, payload) {
      this.uiFlags.isSaving = true;
      try {
        const { data } = await CrmStagesAPI.createStage(pipelineId, payload);
        this.stages = [...this.stages, data];
        return data;
      } finally {
        this.uiFlags.isSaving = false;
      }
    },

    async updateStage(pipelineId, stageId, payload) {
      this.uiFlags.isSaving = true;
      try {
        const { data } = await CrmStagesAPI.updateStage(
          pipelineId,
          stageId,
          payload
        );
        this.stages = this.stages.map(stage =>
          stage.id === data.id ? data : stage
        );
        return data;
      } finally {
        this.uiFlags.isSaving = false;
      }
    },

    async deleteStage(pipelineId, stageId) {
      await CrmStagesAPI.deleteStage(pipelineId, stageId);
      this.stages = this.stages.filter(stage => stage.id !== stageId);
    },

    /**
     * Persists a drag on the stage list. There is no bulk endpoint, so the new order is written
     * one stage at a time — and only for the stages whose position actually changed, which keeps
     * a single-row drag to a single request instead of rewriting the whole column set.
     *
     * @param {number} pipelineId Pipeline owning the stages.
     * @param {Array} orderedStages Stages in the order the list ended up in.
     */
    async reorderStages(pipelineId, orderedStages) {
      const changed = orderedStages
        .map((stage, index) => ({ stage, position: index }))
        .filter(({ stage, position }) => stage.position !== position);

      this.stages = orderedStages.map((stage, index) => ({
        ...stage,
        position: index,
      }));

      this.uiFlags.isSaving = true;
      try {
        await Promise.all(
          changed.map(({ stage, position }) =>
            CrmStagesAPI.updateStage(pipelineId, stage.id, { position })
          )
        );
      } finally {
        this.uiFlags.isSaving = false;
      }
    },

    // --- sources ------------------------------------------------------------------------

    async fetchSources() {
      this.uiFlags.fetchingSources = true;
      try {
        const { data } = await CrmSourcesAPI.get({ include_inactive: true });
        this.sources = data.payload;
        return this.sources;
      } finally {
        this.uiFlags.fetchingSources = false;
      }
    },

    async createSource(payload) {
      this.uiFlags.isSaving = true;
      try {
        const { data } = await CrmSourcesAPI.create(payload);
        this.sources = [...this.sources, data];
        return data;
      } finally {
        this.uiFlags.isSaving = false;
      }
    },

    async updateSource(id, payload) {
      this.uiFlags.isSaving = true;
      try {
        const { data } = await CrmSourcesAPI.update(id, payload);
        this.sources = this.sources.map(source =>
          source.id === data.id ? data : source
        );
        return data;
      } finally {
        this.uiFlags.isSaving = false;
      }
    },

    /**
     * Mints the credential an external system uses to post leads. The plain token comes back once
     * and is NOT kept in the store beyond what the caller does with it: the backend only stores a
     * digest, so it can never be read again — only replaced.
     *
     * @param {number} id Source to credential.
     * @returns {Promise<{token: string, ingestion_url: string}>} The one-time token and where to post.
     */
    async regenerateSourceToken(id) {
      this.uiFlags.isSaving = true;
      try {
        const { data } = await CrmSourcesAPI.regenerateToken(id);
        const { token, ingestion_url: ingestionUrl, ...source } = data;
        this.sources = this.sources.map(item =>
          item.id === source.id ? { ...item, ...source } : item
        );
        return { token, ingestionUrl };
      } finally {
        this.uiFlags.isSaving = false;
      }
    },

    // --- lost reasons -------------------------------------------------------------------

    async fetchLostReasons() {
      this.uiFlags.fetchingLostReasons = true;
      try {
        const { data } = await CrmLostReasonsAPI.get({
          include_inactive: true,
        });
        this.lostReasons = data.payload;
        return this.lostReasons;
      } finally {
        this.uiFlags.fetchingLostReasons = false;
      }
    },

    async createLostReason(payload) {
      this.uiFlags.isSaving = true;
      try {
        const { data } = await CrmLostReasonsAPI.create(payload);
        this.lostReasons = [...this.lostReasons, data];
        return data;
      } finally {
        this.uiFlags.isSaving = false;
      }
    },

    async updateLostReason(id, payload) {
      this.uiFlags.isSaving = true;
      try {
        const { data } = await CrmLostReasonsAPI.update(id, payload);
        this.lostReasons = this.lostReasons.map(reason =>
          reason.id === data.id ? data : reason
        );
        return data;
      } finally {
        this.uiFlags.isSaving = false;
      }
    },
  },
});
