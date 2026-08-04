import { setActivePinia, createPinia } from 'pinia';
import { mount, flushPromises } from '@vue/test-utils';
import { nextTick } from 'vue';

import { useCrmSettingsStore } from 'dashboard/store/crm/settings';
import SourceDialog from '../SourceDialog.vue';

vi.mock('dashboard/api/crm/pipelines', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/stages', () => ({
  default: { getStages: vi.fn() },
}));
vi.mock('dashboard/api/crm/sources', () => ({
  default: { get: vi.fn(), create: vi.fn(), update: vi.fn() },
}));
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

const EXISTING_SOURCE = {
  id: 3,
  name: 'Landing arroba',
  kind: 'landing',
  identifier: 'landing-arroba',
  inbox_id: 8,
  active: false,
};

const mountDialog = () =>
  mount(SourceDialog, { global: { stubs: { Dialog: DialogStub } } });

const openWith = async (wrapper, source = null) => {
  wrapper.vm.open(source);
  await nextTick();
};

const textInputs = wrapper => wrapper.findAll('input[type="text"]');
const confirm = wrapper => wrapper.get('[data-testid="confirm"]');

describe('SourceDialog.vue', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useCrmSettingsStore();
  });

  it('opens blank for a new source and refuses to save without a name', async () => {
    const wrapper = mountDialog();
    await openWith(wrapper);

    expect(wrapper.text()).toContain('New source');
    expect(confirm(wrapper).attributes('disabled')).toBeDefined();
  });

  it('does not create a source when it is confirmed blank', async () => {
    const createSource = vi.spyOn(store, 'createSource').mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper);

    // Straight from the dialog, so the guard inside the form is what stops it
    // and not the disabled button.
    wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');
    await flushPromises();

    expect(createSource).not.toHaveBeenCalled();
    expect(wrapper.emitted('saved')).toBeUndefined();
  });

  it('creates the source with the kind and inbox that were picked', async () => {
    const createSource = vi.spyOn(store, 'createSource').mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper);

    await textInputs(wrapper)[0].setValue('  Landing arroba  ');
    await textInputs(wrapper)[1].setValue('  landing-arroba  ');
    await wrapper.findAll('select')[0].setValue('landing');
    await wrapper.findAll('select')[1].setValue('8');
    await confirm(wrapper).trigger('click');
    await flushPromises();

    expect(createSource).toHaveBeenCalledWith({
      name: 'Landing arroba',
      kind: 'landing',
      identifier: 'landing-arroba',
      active: true,
      inbox_id: 8,
    });
    expect(wrapper.emitted('saved')).toBeTruthy();
  });

  // `import` and `manual` sources are fed by a person, so there is no inbox to
  // register the contacts of a lead in.
  it('drops the inbox for a kind that has nothing to point at', async () => {
    const createSource = vi.spyOn(store, 'createSource').mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper);

    await textInputs(wrapper)[0].setValue('Planilha de leads');
    await wrapper.findAll('select')[0].setValue('import');

    expect(wrapper.findAll('select')).toHaveLength(1);

    await confirm(wrapper).trigger('click');
    await flushPromises();

    expect(createSource).toHaveBeenCalledWith(
      expect.objectContaining({ kind: 'import', inbox_id: null })
    );
  });

  // The kinds that ingest from outside Chatwoot still need an inbox: the
  // contact of every lead they create is registered there.
  it('explains why an external kind still needs an inbox', async () => {
    const wrapper = mountDialog();
    await openWith(wrapper);

    expect(wrapper.text()).toContain('Deals ingested from that inbox');

    await wrapper.findAll('select')[0].setValue('n8n');

    expect(wrapper.text()).toContain(
      'Where the contacts this source creates are registered'
    );
  });

  it('opens prefilled for an existing source and updates it', async () => {
    const updateSource = vi.spyOn(store, 'updateSource').mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper, EXISTING_SOURCE);

    expect(wrapper.text()).toContain('Edit source');
    expect(textInputs(wrapper)[0].element.value).toBe('Landing arroba');
    expect(textInputs(wrapper)[1].element.value).toBe('landing-arroba');

    await textInputs(wrapper)[0].setValue('Landing arroba 2026');
    await confirm(wrapper).trigger('click');
    await flushPromises();

    expect(updateSource).toHaveBeenCalledWith(3, {
      name: 'Landing arroba 2026',
      kind: 'landing',
      identifier: 'landing-arroba',
      active: false,
      inbox_id: 8,
    });
  });

  it('leaves the inbox empty when the source points at none', async () => {
    const createSource = vi.spyOn(store, 'createSource').mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper);

    await textInputs(wrapper)[0].setValue('Sem caixa');
    await confirm(wrapper).trigger('click');
    await flushPromises();

    expect(createSource).toHaveBeenCalledWith(
      expect.objectContaining({ inbox_id: null, identifier: '' })
    );
  });
});
