import { setActivePinia, createPinia } from 'pinia';
import { mount, flushPromises } from '@vue/test-utils';
import { nextTick } from 'vue';

import { useCrmBoardStore } from 'dashboard/store/crm/board';
import CrmDealsAPI from 'dashboard/api/crm/deals';
import { useAlert } from 'dashboard/composables';
import DealFormModal from '../DealFormModal.vue';

vi.mock('dashboard/api/crm/deals', () => ({
  default: { get: vi.fn(), move: vi.fn(), create: vi.fn() },
}));
vi.mock('dashboard/api/crm/pipelines', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/stages', () => ({
  default: { getStages: vi.fn() },
}));
vi.mock('dashboard/api/crm/lostReasons', () => ({
  default: { get: vi.fn() },
}));
vi.mock('dashboard/api/crm/sources', () => ({ default: { get: vi.fn() } }));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: () => ({ value: [{ id: 5, available_name: 'Ana Souza' }] }),
  useStoreGetters: () => ({}),
}));

// The contact list comes from the same searcher the compose flow uses; it keeps
// an AbortController of its own, which has nothing to say about this form.
const { searchContacts } = vi.hoisted(() => ({ searchContacts: vi.fn() }));

vi.mock(
  'dashboard/components-next/NewConversation/helpers/composeConversationHelper',
  () => ({ createContactSearcher: () => searchContacts })
);

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

const CONTACTS = [
  { id: 31, name: 'Maria Silva', email: 'maria@fazenda.com' },
  { id: 32, name: 'João Lima', email: '', phoneNumber: '+5533999999999' },
];

const CREATED_DEAL = {
  id: 99,
  stage_id: 10,
  position: '1000.0',
  title: 'Maria Silva',
  value_cents: 450000,
  currency: 'USD',
  status: 'open',
  contact: { name: 'Maria Silva' },
};

const mountModal = () =>
  mount(DealFormModal, { global: { stubs: { Dialog: DialogStub } } });

const openWith = async (wrapper, stageId) => {
  wrapper.vm.open(stageId);
  await nextTick();
};

const confirm = wrapper => wrapper.get('[data-testid="confirm"]');

const openContactPicker = wrapper =>
  wrapper.findComponent({ name: 'ComboBox' }).get('button').trigger('click');

const pickFirstContact = async wrapper => {
  await openContactPicker(wrapper);
  await flushPromises();
  await wrapper.findAll('[role="option"]')[0].trigger('click');
};

describe('DealFormModal.vue', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useCrmBoardStore();
    store.pipelines = [{ id: 1, settings: { moeda_padrao: 'USD' } }];
    store.selectedPipelineId = 1;
    store.stages = [
      {
        id: 10,
        name: 'Qualification',
        category: 'open',
        deals_count: 0,
        deals_value_cents: 0,
      },
      {
        id: 20,
        name: 'Negotiation',
        category: 'open',
        deals_count: 0,
        deals_value_cents: 0,
      },
    ];
    searchContacts.mockResolvedValue(CONTACTS);
    CrmDealsAPI.create.mockResolvedValue({ data: CREATED_DEAL });
  });

  it('lands on the first column when no column was asked for', async () => {
    const wrapper = mountModal();
    await openWith(wrapper);

    expect(wrapper.text()).toContain('New deal');
    expect(wrapper.findAll('select')[0].element.value).toBe('10');
  });

  it('opens on the column the card was added from', async () => {
    const wrapper = mountModal();
    await openWith(wrapper, 20);

    expect(wrapper.findAll('select')[0].element.value).toBe('20');
  });

  // A card always belongs to a contact and to a column, and it has to be
  // called something.
  it('refuses to submit until the contact and the title are filled in', async () => {
    const wrapper = mountModal();
    await openWith(wrapper);

    expect(confirm(wrapper).attributes('disabled')).toBeDefined();

    await wrapper.get('input[type="text"]').setValue('Lote de 30 novilhas');

    expect(confirm(wrapper).attributes('disabled')).toBeDefined();

    await pickFirstContact(wrapper);

    expect(confirm(wrapper).attributes('disabled')).toBeUndefined();
  });

  it('does not create a deal when it is confirmed incomplete', async () => {
    const wrapper = mountModal();
    await openWith(wrapper);

    // Straight from the dialog, so the guard inside the form is what stops it
    // and not the disabled button.
    wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');
    await flushPromises();

    expect(CrmDealsAPI.create).not.toHaveBeenCalled();
  });

  it('offers the contacts of the account as soon as the picker opens', async () => {
    const wrapper = mountModal();
    await openWith(wrapper);

    await openContactPicker(wrapper);
    await flushPromises();

    expect(searchContacts).toHaveBeenCalledWith('', {
      skipMinLength: true,
      reachableOnly: false,
    });
    expect(wrapper.text()).toContain('Maria Silva (maria@fazenda.com)');
    expect(wrapper.text()).toContain('João Lima');
  });

  // The card is named after whoever it is about until someone renames it, the
  // same fallback the automatic ingestion uses.
  it('names the card after the contact that was picked', async () => {
    const wrapper = mountModal();
    await openWith(wrapper);

    await pickFirstContact(wrapper);

    expect(wrapper.get('input[type="text"]').element.value).toBe('Maria Silva');
  });

  it('keeps a title the user had already written', async () => {
    const wrapper = mountModal();
    await openWith(wrapper);

    await wrapper.get('input[type="text"]').setValue('Lote de 30 novilhas');
    await pickFirstContact(wrapper);

    expect(wrapper.get('input[type="text"]').element.value).toBe(
      'Lote de 30 novilhas'
    );
  });

  it('creates the card in the currency the funnel hands to its cards', async () => {
    const wrapper = mountModal();
    await openWith(wrapper);

    await pickFirstContact(wrapper);
    await wrapper.get('input[type="text"]').setValue('Lote de 30 novilhas');
    await wrapper.get('input[type="number"]').setValue('4500');
    await confirm(wrapper).trigger('click');
    await flushPromises();

    expect(CrmDealsAPI.create).toHaveBeenCalledWith({
      pipeline_id: 1,
      stage_id: 10,
      contact_id: 31,
      title: 'Lote de 30 novilhas',
      value_cents: 450000,
      currency: 'USD',
    });
    expect(useAlert).toHaveBeenCalledWith('Deal created');
    expect(wrapper.emitted('created')).toBeTruthy();
  });

  it('puts the card it just created on the board', async () => {
    const wrapper = mountModal();
    await openWith(wrapper);

    await pickFirstContact(wrapper);
    await confirm(wrapper).trigger('click');
    await flushPromises();

    const column = store.getDealsByStage(10);
    expect(column).toHaveLength(1);
    expect(column[0].title).toBe('Maria Silva');
    // The column header counts what the board now holds.
    expect(store.stages[0].deals_count).toBe(1);
  });

  it('sends the owner and the close date only when they were given', async () => {
    const wrapper = mountModal();
    await openWith(wrapper);

    await pickFirstContact(wrapper);
    await wrapper.findAll('select')[1].setValue('5');
    await wrapper.get('input[type="date"]').setValue('2026-06-30');
    await confirm(wrapper).trigger('click');
    await flushPromises();

    expect(CrmDealsAPI.create).toHaveBeenCalledWith(
      expect.objectContaining({
        owner_id: 5,
        expected_close_on: '2026-06-30',
      })
    );
  });

  it('says so when the card could not be created', async () => {
    CrmDealsAPI.create.mockRejectedValue(new Error('boom'));
    const wrapper = mountModal();
    await openWith(wrapper);

    await pickFirstContact(wrapper);
    await confirm(wrapper).trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Could not create the deal');
    expect(wrapper.emitted('created')).toBeUndefined();
    expect(store.getDealsByStage(10)).toHaveLength(0);
  });
});
