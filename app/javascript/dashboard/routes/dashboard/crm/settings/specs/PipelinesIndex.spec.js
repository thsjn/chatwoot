import { setActivePinia, createPinia } from 'pinia';
import { mount, flushPromises } from '@vue/test-utils';

import { useCrmSettingsStore } from 'dashboard/store/crm/settings';
import CrmPipelinesAPI from 'dashboard/api/crm/pipelines';
import { useAlert } from 'dashboard/composables';
import PipelinesIndex from '../PipelinesIndex.vue';

vi.mock('dashboard/api/crm/pipelines', () => ({
  default: {
    get: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
    archive: vi.fn(),
    unarchive: vi.fn(),
  },
}));
vi.mock('dashboard/api/crm/stages', () => ({
  default: { getStages: vi.fn() },
}));
vi.mock('dashboard/api/crm/sources', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/lostReasons', () => ({
  default: { get: vi.fn() },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const { inboxes } = vi.hoisted(() => ({
  inboxes: {
    value: [
      { id: 7, name: 'WhatsApp Vendas' },
      { id: 8, name: 'Site' },
    ],
  },
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: () => inboxes,
  useStoreGetters: () => ({
    'globalConfig/isACustomBrandedInstance': { value: false },
  }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 } }),
  useRouter: () => ({ push: vi.fn() }),
}));

// `woot-delete-modal` is registered globally in the app. It is doubled by its
// contract: it renders the question while open and answers the two buttons the
// screen wired its confirmation to.
const DeleteModalStub = {
  props: {
    show: { type: Boolean, default: false },
    onClose: { type: Function, default: () => {} },
    onConfirm: { type: Function, default: () => {} },
    title: { type: String, default: '' },
    message: { type: String, default: '' },
    messageValue: { type: String, default: '' },
    confirmText: { type: String, default: '' },
    rejectText: { type: String, default: '' },
  },
  template: `
    <div v-if="show" data-testid="confirmation">
      <h3>{{ title }}</h3>
      <p>{{ message }}{{ messageValue }}</p>
      <button data-testid="reject" @click="onClose">{{ rejectText }}</button>
      <button data-testid="accept" @click="onConfirm">{{ confirmText }}</button>
    </div>
  `,
};

const PIPELINES = [
  {
    id: 1,
    name: 'Vendas',
    description: 'Funil principal',
    is_default: true,
    archived_at: null,
    settings: { moeda_padrao: 'BRL', inbox_ids: [7] },
  },
  {
    id: 2,
    name: 'Pós-venda',
    description: '',
    is_default: false,
    archived_at: null,
    settings: { moeda_padrao: 'USD', inbox_ids: [] },
  },
];

// The settings chrome is shared by every administration screen and belongs to
// its own specs; the default slot has to survive, it is where the dialogs live.
const SettingsLayoutStub = {
  template: '<main><slot name="header" /><slot name="body" /><slot /></main>',
};

const SettingsHeaderStub = {
  props: {
    title: { type: String, default: '' },
    description: { type: String, default: '' },
  },
  template: `
    <header>
      <h1>{{ title }}</h1>
      <p>{{ description }}</p>
      <slot name="actions" />
    </header>
  `,
};

const mountIndex = () =>
  mount(PipelinesIndex, {
    global: {
      components: { 'woot-delete-modal': DeleteModalStub },
      stubs: {
        PipelineDialog: true,
        SettingsLayout: SettingsLayoutStub,
        BaseSettingsHeader: SettingsHeaderStub,
      },
    },
  });

// The row actions are icon-only buttons, so the icon they carry is the only
// thing that separates "archive" from "delete" on screen.
const rowButtons = (wrapper, icon) =>
  wrapper
    .findAllComponents({ name: 'Button' })
    .filter(button => button.props('icon') === icon);

describe('PipelinesIndex.vue', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useCrmSettingsStore();
    CrmPipelinesAPI.get.mockResolvedValue({ data: { payload: PIPELINES } });
  });

  it('lists every pipeline with its currency and marks the default one', async () => {
    const wrapper = mountIndex();
    await flushPromises();

    expect(wrapper.text()).toContain('Vendas');
    expect(wrapper.text()).toContain('Funil principal');
    expect(wrapper.text()).toContain('BRL');
    expect(wrapper.text()).toContain('Pós-venda');
    expect(wrapper.text()).toContain('USD');
    expect(wrapper.text()).toContain('Default');
  });

  // The archived listing is what this screen is for: a retired funnel has to
  // stay visible here to be restored.
  it('asks for the archived pipelines too and marks them', async () => {
    CrmPipelinesAPI.get.mockResolvedValue({
      data: {
        payload: [{ ...PIPELINES[0], archived_at: 1700000000 }, PIPELINES[1]],
      },
    });
    const wrapper = mountIndex();
    await flushPromises();

    expect(CrmPipelinesAPI.get).toHaveBeenCalledWith({
      include_archived: true,
    });
    expect(wrapper.text()).toContain('Archived');
  });

  // The inbox selection IS the switch of the automatic ingestion, so the column
  // names the inboxes whose conversations are about to become cards.
  it('names the inboxes that feed each funnel', async () => {
    const wrapper = mountIndex();
    await flushPromises();

    expect(wrapper.text()).toContain('WhatsApp Vendas');
  });

  it('says the ingestion is off for a funnel with no inbox picked', async () => {
    CrmPipelinesAPI.get.mockResolvedValue({
      data: { payload: [PIPELINES[1]] },
    });
    const wrapper = mountIndex();
    await flushPromises();

    expect(wrapper.text()).toContain('Off');
    expect(wrapper.text()).not.toContain('WhatsApp Vendas');
  });

  it('says so when the account has no pipeline yet', async () => {
    CrmPipelinesAPI.get.mockResolvedValue({ data: { payload: [] } });
    const wrapper = mountIndex();
    await flushPromises();

    expect(wrapper.text()).toContain('No pipelines yet');
  });

  it('archives a pipeline only after the confirmation step', async () => {
    const setPipelineArchived = vi
      .spyOn(store, 'setPipelineArchived')
      .mockResolvedValue({});
    const wrapper = mountIndex();
    await flushPromises();

    await rowButtons(wrapper, 'i-lucide-archive')[0].trigger('click');

    expect(setPipelineArchived).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('Archive pipeline');
    expect(wrapper.text()).toContain('every deal in it is kept');
    expect(wrapper.text()).toContain('Vendas?');

    await wrapper.get('[data-testid="accept"]').trigger('click');
    await flushPromises();

    expect(setPipelineArchived).toHaveBeenCalledWith(1, true);
    expect(useAlert).toHaveBeenCalledWith('Pipeline archived');
  });

  it('leaves the pipeline alone when the confirmation is rejected', async () => {
    const setPipelineArchived = vi
      .spyOn(store, 'setPipelineArchived')
      .mockResolvedValue({});
    const wrapper = mountIndex();
    await flushPromises();

    await rowButtons(wrapper, 'i-lucide-archive')[0].trigger('click');
    await wrapper.get('[data-testid="reject"]').trigger('click');

    expect(setPipelineArchived).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="confirmation"]').exists()).toBe(false);
  });

  it('offers to restore an archived pipeline instead of archiving it', async () => {
    CrmPipelinesAPI.get.mockResolvedValue({
      data: { payload: [{ ...PIPELINES[0], archived_at: 1700000000 }] },
    });
    const setPipelineArchived = vi
      .spyOn(store, 'setPipelineArchived')
      .mockResolvedValue({});
    const wrapper = mountIndex();
    await flushPromises();

    await rowButtons(wrapper, 'i-lucide-archive-restore')[0].trigger('click');

    expect(wrapper.text()).toContain('Restore pipeline');
    expect(wrapper.text()).toContain('with its deals exactly as they were');

    await wrapper.get('[data-testid="accept"]').trigger('click');
    await flushPromises();

    expect(setPipelineArchived).toHaveBeenCalledWith(1, false);
    expect(useAlert).toHaveBeenCalledWith('Pipeline restored');
  });

  // A pipeline that still holds deals is refused with the reason, and that
  // reason is more useful than a generic failure.
  it('surfaces the reason the backend refused a deletion', async () => {
    vi.spyOn(store, 'deletePipeline').mockRejectedValue({
      response: { data: { message: 'Cannot delete a pipeline with deals' } },
    });
    const wrapper = mountIndex();
    await flushPromises();

    await rowButtons(wrapper, 'i-woot-bin')[0].trigger('click');
    await wrapper.get('[data-testid="accept"]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'Cannot delete a pipeline with deals'
    );
  });
});
