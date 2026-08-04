import { setActivePinia, createPinia } from 'pinia';
import CrmPipelinesAPI from 'dashboard/api/crm/pipelines';
import { useCrmSettingsStore } from '../settings';

vi.mock('dashboard/api/crm/pipelines', () => ({
  default: { get: vi.fn(), create: vi.fn(), update: vi.fn() },
}));
vi.mock('dashboard/api/crm/stages', () => ({
  default: { getStages: vi.fn() },
}));
vi.mock('dashboard/api/crm/sources', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/lostReasons', () => ({ default: { get: vi.fn() } }));

const pipeline = (id, isDefault = false) => ({
  id,
  name: `Funil ${id}`,
  is_default: isDefault,
});

describe('crmSettings store', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useCrmSettingsStore();
    vi.clearAllMocks();
  });

  // The backend swaps the default instead of refusing the write, and it only answers with the
  // pipeline that was written — so the list has to drop the flag from the previous default or the
  // badge shows on two rows until the screen is fetched again.
  describe('default pipeline swap', () => {
    it('drops the flag from the previous default when one is updated', async () => {
      store.pipelines = [pipeline(1, true), pipeline(2), pipeline(3)];
      CrmPipelinesAPI.update.mockResolvedValue({ data: pipeline(2, true) });

      await store.updatePipeline(2, { is_default: true });

      expect(store.pipelines.map(item => item.is_default)).toEqual([
        false,
        true,
        false,
      ]);
    });

    it('drops the flag from the previous default when one is created', async () => {
      store.pipelines = [pipeline(1, true)];
      CrmPipelinesAPI.create.mockResolvedValue({ data: pipeline(9, true) });

      await store.createPipeline({ name: 'Funil 9', is_default: true });

      expect(store.pipelines.map(item => item.is_default)).toEqual([
        false,
        true,
      ]);
    });

    it('leaves the other pipelines alone when the saved one is not the default', async () => {
      store.pipelines = [pipeline(1, true), pipeline(2)];
      CrmPipelinesAPI.update.mockResolvedValue({
        data: { ...pipeline(2), name: 'Renomeado' },
      });

      await store.updatePipeline(2, { name: 'Renomeado' });

      expect(store.pipelines[0].is_default).toBe(true);
      expect(store.pipelines[1].name).toBe('Renomeado');
    });
  });
});
