import { setActivePinia, createPinia } from 'pinia';
import CrmDealsAPI from 'dashboard/api/crm/deals';
import { useCrmBoardStore } from '../board';

vi.mock('dashboard/api/crm/deals', () => ({
  default: { get: vi.fn(), move: vi.fn() },
}));
vi.mock('dashboard/api/crm/pipelines', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/stages', () => ({
  default: { getStages: vi.fn() },
}));
vi.mock('dashboard/api/crm/lostReasons', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/sources', () => ({ default: { get: vi.fn() } }));

// Positions arrive as strings ("1000.0"): the backend column is a Postgres numeric and Rails
// serialises BigDecimal as a string, which is what the store normalizes on ingest.
const payload = (id, stageId, overrides = {}) => ({
  id,
  pipeline_id: 1,
  stage_id: stageId,
  title: `Deal ${id}`,
  position: '1500.0',
  lock_version: 2,
  status: 'open',
  value_cents: 100,
  archived_at: null,
  ...overrides,
});

const seedBoard = store => {
  store.selectedPipelineId = 1;
  store.stages = [
    { id: 10, category: 'open', deals_count: 1, deals_value_cents: 100 },
    { id: 20, category: 'open', deals_count: 0, deals_value_cents: 0 },
  ];
  store.deals = {
    10: [
      {
        id: 1,
        pipeline_id: 1,
        stage_id: 10,
        title: 'Deal 1',
        position: 1000,
        lock_version: 1,
        status: 'open',
        value_cents: 100,
        archived_at: null,
      },
    ],
    20: [],
  };
  store.dealsMeta = {
    10: { count: 1, currentPage: 1, isFetching: false },
    20: { count: 0, currentPage: 1, isFetching: false },
  };
};

describe('crmBoard realtime', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useCrmBoardStore();
    seedBoard(store);
    vi.clearAllMocks();
  });

  describe('applyRealtimeDeal', () => {
    it('moves a card between columns without refetching the board', () => {
      store.applyRealtimeDeal(payload(1, 20));

      expect(store.getDealsByStage(10)).toEqual([]);
      expect(store.getDealsByStage(20).map(deal => deal.id)).toEqual([1]);
      expect(store.getDeal(1).position).toBe(1500);
      expect(CrmDealsAPI.get).not.toHaveBeenCalled();
    });

    it('keeps the column sorted when a foreign card is inserted', () => {
      store.applyRealtimeDeal(payload(2, 10, { position: '500.0' }));

      expect(store.getDealsByStage(10).map(deal => deal.id)).toEqual([2, 1]);
      expect(store.getStageMeta(10).count).toBe(2);
    });

    it('merges over the card already on the board instead of replacing it', () => {
      store.deals[10][0].conversations = [{ id: 99 }];

      store.applyRealtimeDeal(payload(1, 10, { title: 'Renamed' }));

      expect(store.getDeal(1).title).toBe('Renamed');
      expect(store.getDeal(1).conversations).toEqual([{ id: 99 }]);
    });

    it('updates the stage aggregates of both ends of the move', () => {
      store.applyRealtimeDeal(payload(1, 20));

      expect(store.stages[0].deals_count).toBe(0);
      expect(store.stages[0].deals_value_cents).toBe(0);
      expect(store.stages[1].deals_count).toBe(1);
      expect(store.stages[1].deals_value_cents).toBe(100);
    });

    it('ignores the echo of a move this board is still waiting on', () => {
      store.pendingMoveDealIds = [1];

      expect(store.applyRealtimeDeal(payload(1, 20))).toBeNull();
      expect(store.getDealsByStage(10).map(deal => deal.id)).toEqual([1]);
      expect(store.getDeal(1).position).toBe(1000);
    });

    it('ignores an event older than the card it holds', () => {
      store.deals[10][0].lock_version = 5;

      expect(
        store.applyRealtimeDeal(payload(1, 20, { lock_version: 4 }))
      ).toBeNull();
      expect(store.getDealsByStage(10).map(deal => deal.id)).toEqual([1]);
    });

    it('drops the card from the board when it is archived', () => {
      store.applyRealtimeDeal(
        payload(1, 10, { archived_at: 1_700_000_000, lock_version: 3 })
      );

      expect(store.getDealsByStage(10)).toEqual([]);
      expect(store.stages[0].deals_count).toBe(0);
    });

    it('puts a restored card back on the board', () => {
      store.deals[10] = [];
      store.dealsMeta[10] = { count: 0, currentPage: 1, isFetching: false };

      store.applyRealtimeDeal(payload(1, 10));

      expect(store.getDealsByStage(10).map(deal => deal.id)).toEqual([1]);
    });

    it('ignores a card from another pipeline', () => {
      expect(
        store.applyRealtimeDeal(payload(2, 10, { pipeline_id: 9 }))
      ).toBeNull();
      expect(store.getDealsByStage(10).map(deal => deal.id)).toEqual([1]);
    });

    it('ignores a card belonging to a column this board never loaded', () => {
      expect(store.applyRealtimeDeal(payload(2, 30))).toBeNull();
    });

    it('does not insert an unknown card while the board is filtered, but keeps updating the visible ones', () => {
      store.filters = { owner_id: 7 };

      expect(store.applyRealtimeDeal(payload(2, 10))).toBeNull();
      store.applyRealtimeDeal(payload(1, 10, { title: 'Still updated' }));

      expect(store.getDeal(1).title).toBe('Still updated');
      expect(store.getDealsByStage(10).map(deal => deal.id)).toEqual([1]);
    });
  });

  describe('applyRealtimeStageRebalance', () => {
    beforeEach(() => {
      CrmDealsAPI.get.mockResolvedValue({
        data: {
          payload: [payload(1, 10, { position: '1000.0' })],
          meta: { count: 1, current_page: 1 },
        },
      });
    });

    it('refetches the renumbered column', async () => {
      await store.applyRealtimeStageRebalance({ stage_id: 10 });

      expect(CrmDealsAPI.get).toHaveBeenCalledWith(
        expect.objectContaining({ stage_id: 10, page: 1 })
      );
    });

    it('ignores a stage outside the board', async () => {
      await store.applyRealtimeStageRebalance({ stage_id: 99 });

      expect(CrmDealsAPI.get).not.toHaveBeenCalled();
    });

    it('defers the refetch while a drag is in flight and replays it when the move settles', async () => {
      let resolveMove;
      CrmDealsAPI.move.mockReturnValue(
        new Promise(resolve => {
          resolveMove = resolve;
        })
      );

      const movePromise = store.moveDeal({
        dealId: 1,
        stageId: 20,
        targetIndex: 0,
      });
      await store.applyRealtimeStageRebalance({ stage_id: 10 });

      expect(CrmDealsAPI.get).not.toHaveBeenCalled();
      expect(store.pendingRebalancedStageIds).toEqual([10]);

      resolveMove({ data: payload(1, 20, { lock_version: 2 }) });
      await movePromise;

      expect(CrmDealsAPI.get).toHaveBeenCalledWith(
        expect.objectContaining({ stage_id: 10, page: 1 })
      );
      expect(store.pendingRebalancedStageIds).toEqual([]);
    });
  });
});
