import { defineStore } from 'pinia';
import CrmPipelinesAPI from 'dashboard/api/crm/pipelines';
import CrmStagesAPI from 'dashboard/api/crm/stages';
import CrmDealsAPI from 'dashboard/api/crm/deals';
import CrmLostReasonsAPI from 'dashboard/api/crm/lostReasons';
import CrmSourcesAPI from 'dashboard/api/crm/sources';

// Mirrors Crm::Deal::POSITION_GAP. Dropping at the edges of a column walks the position by a
// whole gap so there is always room to insert between the new card and its neighbour.
export const POSITION_GAP = 1000;

export const MOVE_ERRORS = {
  conflict: 'CRM.MOVE.CONFLICT',
  wip_limit_exceeded: 'CRM.MOVE.WIP_EXCEEDED',
  lost_reason_required: 'CRM.MOVE.LOST_REASON_REQUIRED',
  generic: 'CRM.MOVE.GENERIC_ERROR',
};

// `position` is a Postgres numeric, and Rails serializes BigDecimal as a JSON string, so it
// arrives as "1000.0". Everything downstream does arithmetic on it, so it is cast on ingest.
const normalizeDeal = deal => ({ ...deal, position: Number(deal.position) });

const byPosition = (a, b) => a.position - b.position || a.id - b.id;

/**
 * Mirrors `Crm::StageAggregatesService`, which totals `.active.open` deals: a card that is
 * archived or already won/lost is on the board but out of the stage header totals. A payload
 * without `status` predates the enum being set and is treated as open, like the column is.
 */
const countsTowardsAggregate = deal =>
  !!deal &&
  deal.status !== 'won' &&
  deal.status !== 'lost' &&
  !deal.archived_at;

/**
 * Fractional indexing: returns the position a card must take to land at `targetIndex` of
 * `list`, where `list` is the destination column WITHOUT the card being moved.
 */
export const calculatePosition = (list, targetIndex) => {
  if (!list.length) return 0;
  if (targetIndex <= 0) return list[0].position - POSITION_GAP;
  if (targetIndex >= list.length)
    return list[list.length - 1].position + POSITION_GAP;

  return (list[targetIndex - 1].position + list[targetIndex].position) / 2;
};

const emptyStageMeta = () => ({ count: 0, currentPage: 0, isFetching: false });

export const useCrmBoardStore = defineStore('crmBoard', {
  state: () => ({
    pipelines: [],
    selectedPipelineId: null,
    stages: [],
    // { [stageId]: Deal[] } — each column kept sorted by position.
    deals: {},
    // { [stageId]: { count, currentPage, isFetching } } — `count` is the server total for the
    // column, which is what tells the board there are more pages to load.
    dealsMeta: {},
    lostReasons: [],
    sources: [],
    filters: {},
    // The archived view swaps the whole board for the cards that left it, so it is a mode and
    // not one more entry in `filters`: it changes what the columns are listing.
    showArchived: false,
    uiFlags: {
      fetchingPipelines: false,
      fetchingStages: false,
      fetchingDeals: false,
      movingDeal: false,
    },
    // { code, messageKey, stageId, dealId } — cleared on every successful move.
    moveError: null,
    // { dealId, stageId, targetIndex } kept while the lost reason modal is open.
    pendingLostReasonMove: null,
    // Ids of the cards this board is dragging right now. A realtime event for one of them is the
    // echo of our own request and must be dropped: the HTTP response is the authoritative one and
    // applying the push first would snap the card back under the cursor.
    pendingMoveDealIds: [],
    // Stages whose rebalance arrived while a drag was in flight, replayed once it settles.
    pendingRebalancedStageIds: [],
  }),

  getters: {
    getPipelines: state => state.pipelines,
    getSelectedPipeline: state =>
      state.pipelines.find(
        pipeline => pipeline.id === state.selectedPipelineId
      ) || null,
    getStages: state => state.stages,
    getLostReasons: state => state.lostReasons,
    getSources: state => state.sources,
    getUIFlags: state => state.uiFlags,
    getFilters: state => state.filters,
    getShowArchived: state => state.showArchived,
    hasActiveFilters: state => Object.keys(state.filters).length > 0,
    getMoveError: state => state.moveError,
    getPendingLostReasonMove: state => state.pendingLostReasonMove,

    getDealsByStage: state => stageId => state.deals[stageId] || [],

    getStageMeta: state => stageId =>
      state.dealsMeta[stageId] || emptyStageMeta(),

    // The column keeps loading while the cards it holds are fewer than the server total.
    hasMoreDeals: state => stageId =>
      (state.deals[stageId] || []).length <
      (state.dealsMeta[stageId]?.count || 0),

    getDeal: state => dealId => {
      const id = Number(dealId);
      return Object.values(state.deals)
        .flat()
        .find(deal => deal.id === id);
    },
  },

  actions: {
    async fetchPipelines() {
      this.uiFlags.fetchingPipelines = true;
      try {
        const { data } = await CrmPipelinesAPI.get();
        this.pipelines = data.payload;
        return this.pipelines;
      } finally {
        this.uiFlags.fetchingPipelines = false;
      }
    },

    async fetchStages(pipelineId) {
      this.uiFlags.fetchingStages = true;
      try {
        const { data } = await CrmStagesAPI.getStages(pipelineId, this.filters);
        // The server totals are authoritative: replacing the whole list discards whatever the
        // board had adjusted locally instead of accumulating on top of it.
        this.stages = data.payload;
        return this.stages;
      } finally {
        this.uiFlags.fetchingStages = false;
      }
    },

    async fetchLostReasons() {
      const { data } = await CrmLostReasonsAPI.get();
      this.lostReasons = data.payload;
      return this.lostReasons;
    },

    async fetchSources() {
      const { data } = await CrmSourcesAPI.get();
      this.sources = data.payload;
      return this.sources;
    },

    async fetchDeals({ stageId, page = 1 } = {}) {
      const meta = this.dealsMeta[stageId] || emptyStageMeta();
      this.dealsMeta[stageId] = { ...meta, isFetching: true };

      try {
        const { data } = await CrmDealsAPI.get({
          pipeline_id: this.selectedPipelineId,
          stage_id: stageId,
          page,
          ...this.filters,
          ...(this.showArchived ? { archived: true } : {}),
        });
        const records = data.payload.map(normalizeDeal);
        const existing = page === 1 ? [] : this.deals[stageId] || [];

        this.deals[stageId] = [...existing, ...records].sort(byPosition);
        this.dealsMeta[stageId] = {
          count: Number(data.meta.count),
          currentPage: Number(data.meta.current_page),
          isFetching: false,
        };
        return this.deals[stageId];
      } catch (error) {
        this.dealsMeta[stageId] = {
          ...this.dealsMeta[stageId],
          isFetching: false,
        };
        throw error;
      }
    },

    async fetchBoardDeals() {
      this.uiFlags.fetchingDeals = true;
      try {
        await Promise.all(
          this.stages.map(stage => this.fetchDeals({ stageId: stage.id }))
        );
      } finally {
        this.uiFlags.fetchingDeals = false;
      }
    },

    async loadMoreDeals(stageId) {
      if (!this.hasMoreDeals(stageId)) return null;

      return this.fetchDeals({
        stageId,
        page: (this.dealsMeta[stageId]?.currentPage || 0) + 1,
      });
    },

    async selectPipeline(pipelineId) {
      this.selectedPipelineId = Number(pipelineId);
      this.deals = {};
      this.dealsMeta = {};
      await this.fetchStages(this.selectedPipelineId);
      await this.fetchBoardDeals();
    },

    // The stage index is refetched along with the cards because the filtered totals in the column
    // headers are computed server side from the very same filters.
    async setFilters(filters = {}) {
      this.filters = filters;
      await this.fetchStages(this.selectedPipelineId);
      await this.fetchBoardDeals();
    },

    async setShowArchived(showArchived) {
      this.showArchived = showArchived;
      this.deals = {};
      this.dealsMeta = {};
      await this.fetchBoardDeals();
    },

    /**
     * Optimistic move: the card lands on the target column before the request leaves, and any
     * failure restores the snapshot taken right before.
     *
     * @returns {Promise<{ success: boolean, errorCode?: string, deal?: Object }>}
     */
    async moveDeal({ dealId, stageId, targetIndex, lostReasonId = null }) {
      const deal = this.getDeal(dealId);
      if (!deal) return { success: false, errorCode: 'deal_not_found' };

      const snapshot = this.captureSnapshot();
      const position = this.applyOptimisticMove({ deal, stageId, targetIndex });

      this.uiFlags.movingDeal = true;
      this.pendingMoveDealIds.push(deal.id);
      try {
        const { data } = await CrmDealsAPI.move(deal.id, {
          stageId,
          position,
          lockVersion: deal.lock_version,
          lostReasonId,
        });
        // The response carries the bumped lock_version: without writing it back, the next move
        // of this same card would be rejected with a 409.
        this.upsertDeal(data);
        this.moveError = null;
        return { success: true, deal: this.getDeal(data.id) };
      } catch (error) {
        return this.handleMoveError(error, {
          snapshot,
          dealId: deal.id,
          stageId,
          targetIndex,
        });
      } finally {
        this.pendingMoveDealIds = this.pendingMoveDealIds.filter(
          id => id !== deal.id
        );
        this.uiFlags.movingDeal = false;
        await this.flushPendingRebalances();
      }
    },

    // Replays the move the board had to abort because the destination stage requires a reason.
    async confirmLostReason(lostReasonId) {
      const pendingMove = this.pendingLostReasonMove;
      if (!pendingMove) return { success: false, errorCode: 'no_pending_move' };

      this.pendingLostReasonMove = null;
      this.moveError = null;
      return this.moveDeal({ ...pendingMove, lostReasonId });
    },

    cancelLostReasonMove() {
      this.pendingLostReasonMove = null;
      this.moveError = null;
    },

    clearMoveError() {
      this.moveError = null;
    },

    /**
     * The ONLY place stage aggregates are touched. `sign` is `1` when the card enters the
     * stage and `-1` when it leaves, so every caller just reports the two ends of the move and
     * a same-stage reorder cancels itself out. Cards that do not count (archived, won, lost)
     * are a no-op, which is what keeps the local totals aligned with the backend query.
     *
     * @param {number|string} stageId Stage owning the column the card enters/leaves.
     * @param {Object} deal Card as it exists on that side of the move.
     * @param {number} sign `1` to add, `-1` to subtract.
     */
    applyAggregateDelta(stageId, deal, sign) {
      if (!countsTowardsAggregate(deal)) return;

      const stage = this.stages.find(item => item.id === Number(stageId));
      if (!stage) return;

      stage.deals_count = Math.max((stage.deals_count || 0) + sign, 0);
      stage.deals_value_cents = Math.max(
        (stage.deals_value_cents || 0) + sign * (deal.value_cents || 0),
        0
      );

      // `filtered_*` only comes back while the board has filters applied. The card being moved is
      // on screen, so it passed the filter and belongs to that subtotal too.
      if (stage.filtered_deals_count === undefined) return;

      stage.filtered_deals_count = Math.max(
        stage.filtered_deals_count + sign,
        0
      );
      stage.filtered_deals_value_cents = Math.max(
        stage.filtered_deals_value_cents + sign * (deal.value_cents || 0),
        0
      );
    },

    upsertDeal(payload) {
      const deal = normalizeDeal(payload);
      this.removeDeal(deal.id);
      this.deals[deal.stage_id] = [
        ...(this.deals[deal.stage_id] || []),
        deal,
      ].sort(byPosition);
      const meta = this.dealsMeta[deal.stage_id] || emptyStageMeta();
      this.dealsMeta[deal.stage_id] = { ...meta, count: meta.count + 1 };
      this.applyAggregateDelta(deal.stage_id, deal, 1);
      return deal;
    },

    removeDeal(dealId) {
      Object.keys(this.deals).forEach(stageId => {
        const column = this.deals[stageId];
        const removed = column.find(deal => deal.id === dealId);
        if (!removed) return;

        this.deals[stageId] = column.filter(deal => deal.id !== dealId);
        const meta = this.dealsMeta[stageId] || emptyStageMeta();
        this.dealsMeta[stageId] = {
          ...meta,
          count: Math.max(meta.count - 1, 0),
        };
        this.applyAggregateDelta(stageId, removed, -1);
      });
    },

    async createDeal(payload) {
      const { data } = await CrmDealsAPI.create(payload);
      return this.upsertDeal(data);
    },

    async updateDeal(dealId, payload) {
      const { data } = await CrmDealsAPI.update(dealId, payload);
      return this.upsertDeal(data);
    },

    // `destroy` archives the deal on the backend, so the card just leaves the board.
    async archiveDeal(dealId) {
      await CrmDealsAPI.delete(dealId);
      this.removeDeal(Number(dealId));
    },

    /**
     * The restored card leaves the archived listing and joins the board, so which of the two the
     * user is looking at decides whether it is dropped or re-inserted.
     */
    async unarchiveDeal(dealId) {
      const { data } = await CrmDealsAPI.unarchive(dealId);
      if (!this.showArchived) return this.upsertDeal(data);

      this.removeDeal(Number(dealId));
      return normalizeDeal(data);
    },

    // --- realtime -----------------------------------------------------------------------

    /**
     * Single entry point for `crm_deal.created|updated|moved|archived`: the four events carry the
     * same card and what the board has to do with it is decided by the payload, not by the name —
     * a card that comes back archived leaves the board no matter which event announced it.
     *
     * The payload is the CARD, not the drawer (the backend leaves the linked conversations out),
     * so it is MERGED over the card already in the store instead of replacing it.
     *
     * @param {Object} payload Deal as broadcast by `Crm::Deal#push_event_data`.
     * @returns {Object|null} The card as it ended up on the board, or `null` when ignored.
     */
    applyRealtimeDeal(payload) {
      const incoming = normalizeDeal(payload);
      const stageId = Number(incoming.stage_id);

      // Another pipeline, or a column this board never loaded: there is nothing to update, and
      // inserting it would invent a card outside the funnel on screen.
      if (
        Number(incoming.pipeline_id) !== this.selectedPipelineId ||
        !this.stages.some(stage => stage.id === stageId)
      ) {
        return null;
      }

      // Our own drag is still in flight for this card — see `pendingMoveDealIds`.
      if (this.pendingMoveDealIds.includes(incoming.id)) return null;

      const existing = this.getDeal(incoming.id);
      // ActionCable gives no ordering guarantee between a push and the response of our own
      // request, and `lock_version` only ever grows, so an older version is a late duplicate.
      if (existing && incoming.lock_version < existing.lock_version)
        return null;

      // Archiving (and restoring) swaps which of the two listings the card belongs to.
      if (this.showArchived !== !!incoming.archived_at) {
        if (!existing) return null;

        this.removeDeal(incoming.id);
        return null;
      }

      // A filtered board cannot tell whether a card it never listed matches the filters, and
      // guessing would show a card that contradicts the filter chip on screen. Cards already
      // rendered keep being updated, which is what matters while someone is watching them.
      if (!existing && this.hasActiveFilters) return null;

      return this.upsertDeal({ ...existing, ...payload });
    },

    /**
     * `Crm::RebalanceStagePositionsJob` renumbered a whole column, so every position this board
     * holds for it is stale and the next drop would compute a midpoint out of numbers that no
     * longer exist. The column is refetched instead of being patched from the event: the request
     * reapplies the visibility policy and the filters currently on screen, which a broadcast
     * carrying raw positions could not do without leaking cards a restricted agent cannot see.
     */
    async applyRealtimeStageRebalance({ stage_id: stageId }) {
      const id = Number(stageId);
      if (!this.stages.some(stage => stage.id === id)) return null;

      // Refetching under a drag would drop the optimistic card, so it waits for the move.
      if (this.pendingMoveDealIds.length) {
        if (!this.pendingRebalancedStageIds.includes(id)) {
          this.pendingRebalancedStageIds.push(id);
        }
        return null;
      }

      return this.fetchDeals({ stageId: id, page: 1 });
    },

    async flushPendingRebalances() {
      if (this.pendingMoveDealIds.length) return;

      const stageIds = this.pendingRebalancedStageIds;
      this.pendingRebalancedStageIds = [];
      await Promise.all(
        stageIds.map(stageId => this.fetchDeals({ stageId, page: 1 }))
      );
    },

    // --- move internals -----------------------------------------------------------------

    captureSnapshot() {
      return {
        deals: Object.fromEntries(
          Object.entries(this.deals).map(([stageId, column]) => [
            stageId,
            [...column],
          ])
        ),
        dealsMeta: Object.fromEntries(
          Object.entries(this.dealsMeta).map(([stageId, meta]) => [
            stageId,
            { ...meta },
          ])
        ),
        // The optimistic move also shifts the column headers, so the totals travel with the
        // cards — otherwise a rollback would put the card back under a wrong count.
        aggregates: this.stages.map(stage => ({
          id: stage.id,
          count: stage.deals_count,
          valueCents: stage.deals_value_cents,
          filteredCount: stage.filtered_deals_count,
          filteredValueCents: stage.filtered_deals_value_cents,
        })),
      };
    },

    restoreSnapshot(snapshot) {
      this.deals = snapshot.deals;
      this.dealsMeta = snapshot.dealsMeta;
      snapshot.aggregates.forEach(entry => {
        const stage = this.stages.find(item => item.id === entry.id);
        if (!stage) return;

        stage.deals_count = entry.count;
        stage.deals_value_cents = entry.valueCents;
        if (entry.filteredCount === undefined) return;

        stage.filtered_deals_count = entry.filteredCount;
        stage.filtered_deals_value_cents = entry.filteredValueCents;
      });
    },

    applyOptimisticMove({ deal, stageId, targetIndex }) {
      this.removeDeal(deal.id);
      const destination = this.deals[stageId] || [];
      const position = calculatePosition(destination, targetIndex);
      // `Crm::MoveDealService` derives the status from the destination stage category (which
      // shares the `open`/`won`/`lost` values), so the card is closed/reopened locally the same
      // way the server is about to do it and the aggregate lands on the final number at once.
      const destinationStage = this.stages.find(item => item.id === stageId);
      const movedDeal = {
        ...deal,
        stage_id: stageId,
        position,
        status: destinationStage?.category || deal.status,
      };

      const nextColumn = [...destination];
      nextColumn.splice(
        Math.min(Math.max(targetIndex, 0), nextColumn.length),
        0,
        movedDeal
      );
      this.deals[stageId] = nextColumn;

      const meta = this.dealsMeta[stageId] || emptyStageMeta();
      this.dealsMeta[stageId] = { ...meta, count: meta.count + 1 };
      this.applyAggregateDelta(stageId, movedDeal, 1);

      return position;
    },

    handleMoveError(error, { snapshot, dealId, stageId, targetIndex }) {
      const status = error.response?.status;
      const errorCode = error.response?.data?.error_code;

      this.restoreSnapshot(snapshot);

      // 409: someone else moved this card first. The body carries the current deal, so the
      // stale card is replaced by the server truth (including its new lock_version).
      if (status === 409) {
        this.upsertDeal(error.response.data);
        this.moveError = {
          code: 'conflict',
          messageKey: MOVE_ERRORS.conflict,
          dealId,
          stageId,
        };
        return { success: false, errorCode: 'conflict' };
      }

      if (errorCode === 'lost_reason_required') {
        this.pendingLostReasonMove = { dealId, stageId, targetIndex };
        this.moveError = {
          code: errorCode,
          messageKey: MOVE_ERRORS.lost_reason_required,
          dealId,
          stageId,
        };
        return { success: false, errorCode };
      }

      if (errorCode === 'wip_limit_exceeded') {
        this.moveError = {
          code: errorCode,
          messageKey: MOVE_ERRORS.wip_limit_exceeded,
          dealId,
          stageId,
        };
        return { success: false, errorCode };
      }

      // The board always sends lock_version, so this code can only mean the card in the store
      // lost it — a bug on our side, not something the user can act on.
      if (errorCode === 'lock_version_required') {
        // eslint-disable-next-line no-console
        console.error(
          `[CRM] move sent without lock_version for deal ${dealId}`
        );
      }

      this.moveError = {
        code: errorCode || 'generic',
        messageKey: MOVE_ERRORS.generic,
        dealId,
        stageId,
      };
      return { success: false, errorCode: errorCode || 'generic' };
    },
  },
});
