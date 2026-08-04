import { setActivePinia, createPinia } from 'pinia';
import { mount, flushPromises } from '@vue/test-utils';

import { useCrmSettingsStore } from 'dashboard/store/crm/settings';
import CrmSourcesAPI from 'dashboard/api/crm/sources';
import { useAlert } from 'dashboard/composables';
import SourcesIndex from '../SourcesIndex.vue';

vi.mock('dashboard/api/crm/sources', () => ({
  default: {
    get: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    regenerateToken: vi.fn(),
  },
}));
vi.mock('dashboard/api/crm/pipelines', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/stages', () => ({
  default: { getStages: vi.fn() },
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
  useStoreGetters: () => ({
    'globalConfig/isACustomBrandedInstance': { value: false },
  }),
}));

const SOURCES = [
  {
    id: 1,
    name: 'Landing arroba',
    kind: 'landing',
    inbox_id: 8,
    has_token: true,
    active: true,
  },
  {
    id: 2,
    name: 'Conversas WhatsApp',
    kind: 'inbox',
    inbox_id: 7,
    has_token: false,
    active: false,
  },
];

// The token dialog has its own spec: here it only has to report which source
// the screen handed it.
const TokenDialogStub = {
  name: 'SourceTokenDialogStub',
  data: () => ({ opened: null }),
  methods: {
    open(source) {
      this.opened = source;
    },
  },
  template: '<div />',
};

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
  mount(SourcesIndex, {
    global: {
      stubs: {
        SourceDialog: true,
        SourceTokenDialog: TokenDialogStub,
        SettingsLayout: SettingsLayoutStub,
        BaseSettingsHeader: SettingsHeaderStub,
      },
    },
  });

// The row actions are icon-only buttons, so the icon they carry is the only
// thing that names them on screen.
const rowButtons = (wrapper, icon) =>
  wrapper
    .findAllComponents({ name: 'Button' })
    .filter(button => button.props('icon') === icon);

describe('SourcesIndex.vue', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useCrmSettingsStore();
    CrmSourcesAPI.get.mockResolvedValue({ data: { payload: SOURCES } });
  });

  // A source is never deleted, so the administration screen has to list the
  // inactive ones too: the `active` flag is what it exists to manage.
  it('lists the inactive sources alongside the active ones', async () => {
    const wrapper = mountIndex();
    await flushPromises();

    expect(CrmSourcesAPI.get).toHaveBeenCalledWith({ include_inactive: true });
    expect(wrapper.text()).toContain('Landing arroba');
    expect(wrapper.text()).toContain('Conversas WhatsApp');
  });

  it('reads the kind and the inbox of every source', async () => {
    const wrapper = mountIndex();
    await flushPromises();

    expect(wrapper.text()).toContain('Landing page');
    expect(wrapper.text()).toContain('Site');
    expect(wrapper.text()).toContain('WhatsApp Vendas');
  });

  it('reports whether a credentialed source already has a token', async () => {
    const wrapper = mountIndex();
    await flushPromises();
    const cells = wrapper.findAll('tbody tr').map(row => row.text());

    expect(cells[0]).toContain('Set');
    // An inbox source is fed by the conversation ingestion, so there is nothing
    // to authenticate and no token status to report.
    expect(cells[1]).not.toContain('Not set');
  });

  it('retires a source by turning it off instead of deleting it', async () => {
    const updateSource = vi
      .spyOn(store, 'updateSource')
      .mockResolvedValue(SOURCES[0]);
    const wrapper = mountIndex();
    await flushPromises();

    expect(rowButtons(wrapper, 'i-woot-bin')).toHaveLength(0);

    await wrapper.findAll('[role="switch"]')[0].trigger('click');
    await flushPromises();

    expect(updateSource).toHaveBeenCalledWith(1, { active: false });
    expect(useAlert).toHaveBeenCalledWith('Source saved');
  });

  it('brings a retired source back by turning it on', async () => {
    const updateSource = vi
      .spyOn(store, 'updateSource')
      .mockResolvedValue(SOURCES[1]);
    const wrapper = mountIndex();
    await flushPromises();

    await wrapper.findAll('[role="switch"]')[1].trigger('click');
    await flushPromises();

    expect(updateSource).toHaveBeenCalledWith(2, { active: true });
  });

  it('says so when the source could not be saved', async () => {
    vi.spyOn(store, 'updateSource').mockRejectedValue(new Error('boom'));
    const wrapper = mountIndex();
    await flushPromises();

    await wrapper.findAll('[role="switch"]')[0].trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Could not save the source');
  });

  // Only the kinds that stand for something outside Chatwoot can be
  // credentialed, so the token action is offered to those alone.
  it('offers the token action only to the sources fed from outside', async () => {
    const wrapper = mountIndex();
    await flushPromises();

    const tokenButtons = rowButtons(wrapper, 'i-lucide-key-round');
    expect(tokenButtons).toHaveLength(1);

    await tokenButtons[0].trigger('click');

    const dialog = wrapper.findComponent({ name: 'SourceTokenDialogStub' });
    expect(dialog.vm.opened.name).toBe('Landing arroba');
  });
});
