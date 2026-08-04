import { setActivePinia, createPinia } from 'pinia';
import { mount, flushPromises } from '@vue/test-utils';
import { nextTick } from 'vue';

import { useCrmSettingsStore } from 'dashboard/store/crm/settings';
import { useAlert } from 'dashboard/composables';
import SourceTokenDialog from '../SourceTokenDialog.vue';

vi.mock('dashboard/api/crm/pipelines', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/stages', () => ({
  default: { getStages: vi.fn() },
}));
vi.mock('dashboard/api/crm/sources', () => ({
  default: { get: vi.fn(), regenerateToken: vi.fn() },
}));
vi.mock('dashboard/api/crm/lostReasons', () => ({
  default: { get: vi.fn() },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

// `<dialog>.showModal()` is not implemented in jsdom, so the dialog is doubled
// by its contract: it renders its content while open and exposes open/close.
const DialogStub = {
  name: 'Dialog',
  props: {
    title: { type: String, default: '' },
    description: { type: String, default: '' },
  },
  emits: ['close'],
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
      <p>{{ description }}</p>
      <slot />
    </div>
  `,
};

// `Code` highlights through a global component the dashboard registers; here it
// only has to make the snippet readable.
const CodeStub = {
  name: 'Code',
  props: { script: { type: String, default: '' } },
  template: '<pre>{{ script }}</pre>',
};

const SOURCE = {
  id: 3,
  name: 'Landing arroba',
  kind: 'landing',
  inbox_id: 8,
  has_token: false,
};

const MINTED = {
  token: 'crm_src_9f2b7c1d',
  ingestionUrl: 'https://app.example.com/crm/ingest/3',
};

const mountDialog = () =>
  mount(SourceTokenDialog, {
    global: { stubs: { Dialog: DialogStub, Code: CodeStub } },
  });

const openWith = async (wrapper, source = SOURCE) => {
  wrapper.vm.open(source);
  await nextTick();
};

const buttonWithText = (wrapper, text) =>
  wrapper.findAll('button').find(button => button.text().includes(text));

describe('SourceTokenDialog.vue', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useCrmSettingsStore();
  });

  it('offers to mint the first token of a source that has none', async () => {
    const wrapper = mountDialog();
    await openWith(wrapper);

    expect(wrapper.text()).toContain('External ingestion token');
    expect(wrapper.text()).toContain('This source has no token yet');
    expect(buttonWithText(wrapper, 'Generate token')).toBeTruthy();
  });

  // The stored token is a digest, so a source that already has one cannot show
  // it again: the only thing on offer is replacing it.
  it('never shows the token of a previous visit, only offers to replace it', async () => {
    const wrapper = mountDialog();
    await openWith(wrapper, { ...SOURCE, has_token: true });

    expect(wrapper.text()).toContain('This source already has a token');
    expect(wrapper.text()).toContain('invalidates the current one immediately');
    expect(buttonWithText(wrapper, 'Regenerate token')).toBeTruthy();
    expect(wrapper.find('pre').exists()).toBe(false);
  });

  it('shows the minted token once, warning it will not be shown again', async () => {
    vi.spyOn(store, 'regenerateSourceToken').mockResolvedValue(MINTED);
    const wrapper = mountDialog();
    await openWith(wrapper);

    await buttonWithText(wrapper, 'Generate token').trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('crm_src_9f2b7c1d');
    expect(wrapper.text()).toContain(
      'this is the only time the token is shown'
    );
    expect(wrapper.text()).toContain('only replaced');
  });

  it('spells out the request that posts a lead into the funnel', async () => {
    vi.spyOn(store, 'regenerateSourceToken').mockResolvedValue(MINTED);
    const wrapper = mountDialog();
    await openWith(wrapper);

    await buttonWithText(wrapper, 'Generate token').trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('How to send a lead');
    expect(wrapper.text()).toContain('https://app.example.com/crm/ingest/3');
    expect(wrapper.text()).toContain('X-Crm-Source-Token: crm_src_9f2b7c1d');
    expect(wrapper.text()).toContain('Either an email or a phone number');
  });

  it('drops the token as soon as the dialog is opened again', async () => {
    vi.spyOn(store, 'regenerateSourceToken').mockResolvedValue(MINTED);
    const wrapper = mountDialog();
    await openWith(wrapper);

    await buttonWithText(wrapper, 'Generate token').trigger('click');
    await flushPromises();

    await openWith(wrapper, { ...SOURCE, has_token: true });

    expect(wrapper.text()).not.toContain('crm_src_9f2b7c1d');
    expect(wrapper.text()).toContain('This source already has a token');
  });

  // The contact of every lead is registered in the inbox the source points at,
  // so a source without one produces a token that cannot ingest anything.
  it('warns that the source needs an inbox before the token is of any use', async () => {
    const wrapper = mountDialog();
    await openWith(wrapper, { ...SOURCE, inbox_id: null });

    expect(wrapper.text()).toContain('Link an inbox to this source');
  });

  it('says nothing about the inbox when the source already points at one', async () => {
    const wrapper = mountDialog();
    await openWith(wrapper);

    expect(wrapper.text()).not.toContain('Link an inbox to this source');
  });

  it('says so when the token could not be minted', async () => {
    vi.spyOn(store, 'regenerateSourceToken').mockRejectedValue({
      response: { data: { message: 'Source is inactive' } },
    });
    const wrapper = mountDialog();
    await openWith(wrapper);

    await buttonWithText(wrapper, 'Generate token').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Source is inactive');
    expect(wrapper.find('pre').exists()).toBe(false);
  });
});
