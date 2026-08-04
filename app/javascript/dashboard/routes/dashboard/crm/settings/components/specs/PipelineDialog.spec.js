import { setActivePinia, createPinia } from 'pinia';
import { mount, flushPromises } from '@vue/test-utils';
import { nextTick } from 'vue';

import { useCrmSettingsStore } from 'dashboard/store/crm/settings';
import PipelineDialog from '../PipelineDialog.vue';

vi.mock('dashboard/api/crm/pipelines', () => ({
  default: { get: vi.fn(), create: vi.fn(), update: vi.fn() },
}));
vi.mock('dashboard/api/crm/stages', () => ({
  default: { getStages: vi.fn() },
}));
vi.mock('dashboard/api/crm/sources', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/lostReasons', () => ({
  default: { get: vi.fn() },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

// The dialog iterates the inbox list straight in the template, so the getter has
// to answer something the renderer unwraps like a ref.
const { inboxState, inboxesRef } = vi.hoisted(() => {
  const state = { list: [] };
  return {
    inboxState: state,
    inboxesRef: {
      __v_isRef: true,
      get value() {
        return state.list;
      },
    },
  };
});

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: () => inboxesRef,
  useStoreGetters: () => ({}),
}));

// `<dialog>.showModal()` is not implemented in jsdom, so the dialog is doubled
// by its contract: it renders the form while open and answers the confirm
// button the dialog is wired to.
const DialogStub = {
  name: 'Dialog',
  props: {
    title: { type: String, default: '' },
    disableConfirmButton: { type: Boolean, default: false },
  },
  emits: ['confirm', 'close'],
  data: () => ({ isOpen: false }),
  methods: {
    open() {
      this.isOpen = true;
    },
    close() {
      this.isOpen = false;
      this.$emit('close');
    },
  },
  template: `
    <div v-if="isOpen" data-testid="dialog">
      <h3>{{ title }}</h3>
      <slot />
      <button
        data-testid="confirm"
        :disabled="disableConfirmButton"
        @click="$emit('confirm')"
      />
    </div>
  `,
};

// A funnel already configured in every corner: the point of the update payload
// is that none of it is lost when only the name changes.
const EXISTING_PIPELINE = {
  id: 4,
  name: 'Vendas',
  description: 'Funil principal',
  is_default: true,
  settings: {
    inbox_ids: ['7'],
    janela_dedupe_dias: 15,
    exige_proxima_atividade: true,
    moeda_padrao: 'USD',
    restrito_por_owner: true,
  },
};

const mountDialog = () =>
  mount(PipelineDialog, { global: { stubs: { Dialog: DialogStub } } });

const openWith = async (wrapper, pipeline = null) => {
  wrapper.vm.open(pipeline);
  await nextTick();
};

const textInputs = wrapper => wrapper.findAll('input[type="text"]');
const confirm = wrapper => wrapper.get('[data-testid="confirm"]');

describe('PipelineDialog.vue', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useCrmSettingsStore();
    inboxState.list = [
      { id: 7, name: 'WhatsApp Vendas' },
      { id: 8, name: 'Site' },
    ];
  });

  it('opens blank for a new pipeline and refuses to save without a name', async () => {
    const wrapper = mountDialog();
    await openWith(wrapper);

    expect(wrapper.text()).toContain('New pipeline');
    expect(confirm(wrapper).attributes('disabled')).toBeDefined();
  });

  it('does not create a pipeline when it is confirmed blank', async () => {
    const createPipeline = vi
      .spyOn(store, 'createPipeline')
      .mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper);

    // Straight from the dialog, so the guard inside the form is what stops it
    // and not the disabled button.
    wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');
    await flushPromises();

    expect(createPipeline).not.toHaveBeenCalled();
    expect(wrapper.emitted('saved')).toBeUndefined();
  });

  // `settings` is written as a WHOLE hash: the backend assignment replaces the
  // stored one, so a payload missing a key would wipe that configuration.
  it('creates the pipeline with the five settings keys filled in', async () => {
    const createPipeline = vi
      .spyOn(store, 'createPipeline')
      .mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper);

    await textInputs(wrapper)[0].setValue('  Pós-venda  ');
    await confirm(wrapper).trigger('click');
    await flushPromises();

    expect(createPipeline).toHaveBeenCalledWith({
      name: 'Pós-venda',
      description: '',
      is_default: false,
      settings: {
        inbox_ids: [],
        janela_dedupe_dias: 30,
        exige_proxima_atividade: false,
        moeda_padrao: 'BRL',
        restrito_por_owner: false,
      },
    });
    expect(wrapper.emitted('saved')).toBeTruthy();
  });

  it('keeps every untouched setting when only the name is edited', async () => {
    const updatePipeline = vi
      .spyOn(store, 'updatePipeline')
      .mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper, EXISTING_PIPELINE);

    expect(wrapper.text()).toContain('Edit pipeline');
    expect(textInputs(wrapper)[0].element.value).toBe('Vendas');

    await textInputs(wrapper)[0].setValue('Vendas Corte');
    await confirm(wrapper).trigger('click');
    await flushPromises();

    expect(updatePipeline).toHaveBeenCalledWith(4, {
      name: 'Vendas Corte',
      description: 'Funil principal',
      is_default: true,
      settings: {
        // The jsonb array comes back with string ids, and the ingestion query
        // only matches the numeric branch.
        inbox_ids: [7],
        janela_dedupe_dias: 15,
        exige_proxima_atividade: true,
        moeda_padrao: 'USD',
        restrito_por_owner: true,
      },
    });
  });

  // Picking an inbox IS the switch of the automatic ingestion: nothing else
  // turns it on, and every conversation in that inbox becomes a card.
  it('says the funnel creates no card of its own while no inbox is picked', async () => {
    const wrapper = mountDialog();
    await openWith(wrapper);

    expect(wrapper.text()).toContain('No inbox selected');
    expect(wrapper.text()).toContain('only added by hand from the board');
    expect(wrapper.text()).not.toContain('Every new conversation');
  });

  it('warns about the ingestion as soon as an inbox is ticked', async () => {
    const wrapper = mountDialog();
    await openWith(wrapper);

    await wrapper.findAll('input[type="checkbox"]')[0].setValue(true);

    expect(wrapper.text()).toContain(
      'Every new conversation in the selected inboxes will create a card'
    );
    expect(wrapper.text()).toContain('really are opportunities');
    expect(wrapper.text()).not.toContain('No inbox selected');
  });

  it('opens an already ingesting funnel with its warning up', async () => {
    const wrapper = mountDialog();
    await openWith(wrapper, EXISTING_PIPELINE);

    expect(wrapper.text()).toContain('Every new conversation');
  });

  it('sends the inbox that was ticked as a number', async () => {
    const createPipeline = vi
      .spyOn(store, 'createPipeline')
      .mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper);

    await textInputs(wrapper)[0].setValue('Vendas');
    await wrapper.findAll('input[type="checkbox"]')[1].setValue(true);
    await confirm(wrapper).trigger('click');
    await flushPromises();

    expect(createPipeline).toHaveBeenCalledWith(
      expect.objectContaining({
        settings: expect.objectContaining({ inbox_ids: [8] }),
      })
    );
  });

  it('normalises the currency the funnel hands to its cards', async () => {
    const createPipeline = vi
      .spyOn(store, 'createPipeline')
      .mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper);

    await textInputs(wrapper)[0].setValue('Vendas');
    await textInputs(wrapper)[1].setValue(' usd ');
    await confirm(wrapper).trigger('click');
    await flushPromises();

    expect(createPipeline).toHaveBeenCalledWith(
      expect.objectContaining({
        settings: expect.objectContaining({ moeda_padrao: 'USD' }),
      })
    );
  });

  // The deduplication window is what keeps a contact from opening a second card,
  // so an emptied field falls back to the shipped default instead of zero.
  it('falls back to the default deduplication window when it is cleared', async () => {
    const createPipeline = vi
      .spyOn(store, 'createPipeline')
      .mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper);

    await textInputs(wrapper)[0].setValue('Vendas');
    await wrapper.get('input[type="number"]').setValue('');
    await confirm(wrapper).trigger('click');
    await flushPromises();

    expect(createPipeline).toHaveBeenCalledWith(
      expect.objectContaining({
        settings: expect.objectContaining({ janela_dedupe_dias: 30 }),
      })
    );
  });

  it('says so when the account has no inbox to offer', async () => {
    inboxState.list = [];
    const wrapper = mountDialog();
    await openWith(wrapper);

    expect(wrapper.text()).toContain('No inboxes in this account');
  });
});
