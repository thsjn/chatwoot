import { setActivePinia, createPinia } from 'pinia';
import CrmDealsAPI from 'dashboard/api/crm/deals';
import CrmStagesAPI from 'dashboard/api/crm/stages';
import { useCrmBoardStore, calculatePosition, POSITION_GAP } from '../board';

vi.mock('dashboard/api/crm/deals', () => ({
  default: {
    get: vi.fn(),
    move: vi.fn(),
    create: vi.fn(),
    delete: vi.fn(),
  },
}));
vi.mock('dashboard/api/crm/pipelines', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/stages', () => ({
  default: { getStages: vi.fn() },
}));
vi.mock('dashboard/api/crm/lostReasons', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/sources', () => ({ default: { get: vi.fn() } }));

const deal = (id, stageId, position, lockVersion = 1, status = 'open') => ({
  id,
  stage_id: stageId,
  position,
  lock_version: lockVersion,
  status,
  title: `Deal ${id}`,
  value_cents: 100,
});

// The header totals only count open, non archived deals, so the seeded numbers ignore the
// card sitting on the lost column — exactly what the backend query returns.
const seedBoard = store => {
  store.selectedPipelineId = 1;
  store.stages = [
    {
      id: 10,
      name: 'New',
      category: 'open',
      deals_count: 2,
      deals_value_cents: 200,
    },
    {
      id: 20,
      name: 'Lost',
      category: 'lost',
      deals_count: 0,
      deals_value_cents: 0,
    },
    {
      id: 30,
      name: 'Negotiation',
      category: 'open',
      deals_count: 0,
      deals_value_cents: 0,
    },
    {
      id: 40,
      name: 'Won',
      category: 'won',
      deals_count: 0,
      deals_value_cents: 0,
    },
  ];
  store.deals = {
    10: [deal(1, 10, 1000), deal(2, 10, 2000)],
    20: [deal(3, 20, 1000, 1, 'lost')],
  };
  store.dealsMeta = {
    10: { count: 2, currentPage: 1, isFetching: false },
    20: { count: 1, currentPage: 1, isFetching: false },
  };
};

const totals = (boardStore, stageId) => {
  const stage = boardStore.stages.find(item => item.id === stageId);
  return [stage.deals_count, stage.deals_value_cents];
};

describe('calculatePosition', () => {
  it('returns 0 for an empty column', () => {
    expect(calculatePosition([], 0)).toBe(0);
  });

  it('walks a full gap below the first card when dropping at the top', () => {
    expect(calculatePosition([{ position: 1000 }], 0)).toBe(
      1000 - POSITION_GAP
    );
  });

  it('walks a full gap above the last card when dropping at the bottom', () => {
    expect(calculatePosition([{ position: 1000 }, { position: 2000 }], 2)).toBe(
      2000 + POSITION_GAP
    );
  });

  it('averages the neighbours when dropping in between', () => {
    expect(calculatePosition([{ position: 1000 }, { position: 2000 }], 1)).toBe(
      1500
    );
  });
});

describe('crm board store', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    store = useCrmBoardStore();
    seedBoard(store);
  });

  it('moves the card locally before the request settles and writes back the lock_version', async () => {
    let resolveMove;
    CrmDealsAPI.move.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveMove = resolve;
        })
    );

    const movePromise = store.moveDeal({
      dealId: 1,
      stageId: 20,
      targetIndex: 0,
    });

    expect(store.getDealsByStage(10).map(d => d.id)).toEqual([2]);
    expect(store.getDealsByStage(20).map(d => d.id)).toEqual([1, 3]);
    expect(CrmDealsAPI.move).toHaveBeenCalledWith(1, {
      stageId: 20,
      position: 0,
      lockVersion: 1,
      lostReasonId: null,
    });

    resolveMove({ data: { ...deal(1, 20, '0.0', 2), status: 'lost' } });
    const result = await movePromise;

    expect(result.success).toBe(true);
    expect(store.getDeal(1).lock_version).toBe(2);
    expect(store.getDeal(1).position).toBe(0);
  });

  it('rolls back and replaces the card with the server deal on a 409 conflict', async () => {
    CrmDealsAPI.move.mockRejectedValue({
      response: { status: 409, data: deal(1, 20, '3000.0', 7, 'lost') },
    });

    const result = await store.moveDeal({
      dealId: 1,
      stageId: 20,
      targetIndex: 0,
    });

    expect(result.errorCode).toBe('conflict');
    expect(store.moveError.messageKey).toBe('CRM.MOVE.CONFLICT');
    expect(store.getDealsByStage(10).map(d => d.id)).toEqual([2]);
    expect(store.getDealsByStage(20).map(d => d.id)).toEqual([3, 1]);
    expect(store.getDeal(1).lock_version).toBe(7);
  });

  it('rolls back and stores the pending move when the stage requires a lost reason', async () => {
    CrmDealsAPI.move.mockRejectedValue({
      response: { status: 422, data: { error_code: 'lost_reason_required' } },
    });

    const result = await store.moveDeal({
      dealId: 1,
      stageId: 20,
      targetIndex: 0,
    });

    expect(result.errorCode).toBe('lost_reason_required');
    expect(store.getDealsByStage(10).map(d => d.id)).toEqual([1, 2]);
    expect(store.getDealsByStage(20).map(d => d.id)).toEqual([3]);
    expect(store.pendingLostReasonMove).toEqual({
      dealId: 1,
      stageId: 20,
      targetIndex: 0,
    });
  });

  it('replays the move with the lost reason once it is confirmed', async () => {
    CrmDealsAPI.move.mockRejectedValueOnce({
      response: { status: 422, data: { error_code: 'lost_reason_required' } },
    });
    await store.moveDeal({ dealId: 1, stageId: 20, targetIndex: 0 });

    CrmDealsAPI.move.mockResolvedValueOnce({
      data: { ...deal(1, 20, '0.0', 2), status: 'lost' },
    });
    const result = await store.confirmLostReason(55);

    expect(result.success).toBe(true);
    expect(CrmDealsAPI.move).toHaveBeenLastCalledWith(1, {
      stageId: 20,
      position: 0,
      lockVersion: 1,
      lostReasonId: 55,
    });
    expect(store.pendingLostReasonMove).toBeNull();
    expect(store.moveError).toBeNull();
  });

  it('rolls back and flags the column limit when the WIP limit is exceeded', async () => {
    CrmDealsAPI.move.mockRejectedValue({
      response: { status: 422, data: { error_code: 'wip_limit_exceeded' } },
    });

    const result = await store.moveDeal({
      dealId: 1,
      stageId: 20,
      targetIndex: 0,
    });

    expect(result.errorCode).toBe('wip_limit_exceeded');
    expect(store.moveError.messageKey).toBe('CRM.MOVE.WIP_EXCEEDED');
    expect(store.getDealsByStage(10).map(d => d.id)).toEqual([1, 2]);
    expect(store.dealsMeta[20].count).toBe(1);
  });

  it('appends the next page of a column and keeps it sorted by position', async () => {
    CrmDealsAPI.get.mockResolvedValue({
      data: {
        payload: [deal(4, 10, '1500.0')],
        meta: { count: 3, current_page: 2 },
      },
    });
    store.dealsMeta[10].count = 3;

    await store.loadMoreDeals(10);

    expect(store.getDealsByStage(10).map(d => d.id)).toEqual([1, 4, 2]);
    expect(store.hasMoreDeals(10)).toBe(false);
  });

  it('moves the header totals along with the card between columns', async () => {
    let resolveMove;
    CrmDealsAPI.move.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveMove = resolve;
        })
    );

    const movePromise = store.moveDeal({
      dealId: 1,
      stageId: 30,
      targetIndex: 0,
    });

    expect(totals(store, 10)).toEqual([1, 100]);
    expect(totals(store, 30)).toEqual([1, 100]);

    resolveMove({ data: deal(1, 30, '0.0', 2) });
    await movePromise;

    expect(totals(store, 10)).toEqual([1, 100]);
    expect(totals(store, 30)).toEqual([1, 100]);
  });

  it('restores the header totals when the move hits a 409 conflict', async () => {
    CrmDealsAPI.move.mockRejectedValue({
      response: { status: 409, data: deal(1, 10, '1500.0', 7) },
    });

    const result = await store.moveDeal({
      dealId: 1,
      stageId: 30,
      targetIndex: 0,
    });

    expect(result.errorCode).toBe('conflict');
    expect(totals(store, 10)).toEqual([2, 200]);
    expect(totals(store, 30)).toEqual([0, 0]);
  });

  it('restores the header totals when the move is rejected with a 422', async () => {
    CrmDealsAPI.move.mockRejectedValue({
      response: { status: 422, data: { error_code: 'wip_limit_exceeded' } },
    });

    const result = await store.moveDeal({
      dealId: 1,
      stageId: 30,
      targetIndex: 0,
    });

    expect(result.errorCode).toBe('wip_limit_exceeded');
    expect(totals(store, 10)).toEqual([2, 200]);
    expect(totals(store, 30)).toEqual([0, 0]);
  });

  it('leaves the header totals untouched on a same column reorder', async () => {
    let resolveMove;
    CrmDealsAPI.move.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveMove = resolve;
        })
    );

    const movePromise = store.moveDeal({
      dealId: 1,
      stageId: 10,
      targetIndex: 2,
    });

    expect(store.getDealsByStage(10).map(d => d.id)).toEqual([2, 1]);
    expect(totals(store, 10)).toEqual([2, 200]);

    resolveMove({ data: deal(1, 10, '3000.0', 2) });
    await movePromise;

    expect(totals(store, 10)).toEqual([2, 200]);
  });

  it('drops the card out of the open totals when the move closes it as won', async () => {
    CrmDealsAPI.move.mockResolvedValue({
      data: deal(1, 40, '0.0', 2, 'won'),
    });

    const result = await store.moveDeal({
      dealId: 1,
      stageId: 40,
      targetIndex: 0,
    });

    expect(result.success).toBe(true);
    expect(store.getDealsByStage(40).map(d => d.id)).toEqual([1]);
    expect(totals(store, 10)).toEqual([1, 100]);
    expect(totals(store, 40)).toEqual([0, 0]);
  });

  it('lets a stage fetch overwrite the locally adjusted totals', async () => {
    CrmDealsAPI.move.mockResolvedValue({ data: deal(1, 30, '0.0', 2) });
    await store.moveDeal({ dealId: 1, stageId: 30, targetIndex: 0 });
    expect(totals(store, 10)).toEqual([1, 100]);

    CrmStagesAPI.getStages.mockResolvedValue({
      data: {
        payload: [
          {
            id: 10,
            name: 'New',
            category: 'open',
            deals_count: 9,
            deals_value_cents: 900,
          },
        ],
      },
    });
    await store.fetchStages(1);

    expect(totals(store, 10)).toEqual([9, 900]);
  });

  it('adds a created card and subtracts an archived one from the totals', async () => {
    CrmDealsAPI.create.mockResolvedValue({ data: deal(9, 10, '3000.0') });
    await store.createDeal({ title: 'Deal 9' });
    expect(totals(store, 10)).toEqual([3, 300]);

    CrmDealsAPI.delete.mockResolvedValue({});
    await store.archiveDeal(9);
    expect(totals(store, 10)).toEqual([2, 200]);
  });
});
