import { setActivePinia, createPinia } from 'pinia';
import { mount, flushPromises } from '@vue/test-utils';

import { useCrmBoardStore } from 'dashboard/store/crm/board';
import { useAlert } from 'dashboard/composables';
import DealCustomAttributes from '../DealCustomAttributes.vue';

vi.mock('dashboard/api/crm/deals', () => ({
  default: { get: vi.fn(), move: vi.fn(), update: vi.fn() },
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

const { definitions } = vi.hoisted(() => ({ definitions: { value: [] } }));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: () => definitions,
  useStoreGetters: () => ({}),
}));

// One definition per display type the sidebar knows how to edit. `text`,
// `link` and `number` share the same inline input editor.
const DEFINITIONS = [
  {
    id: 1,
    attributeKey: 'observacao',
    attributeDisplayName: 'Observação',
    attributeDisplayType: 'text',
  },
  {
    id: 2,
    attributeKey: 'cabecas',
    attributeDisplayName: 'Cabeças',
    attributeDisplayType: 'number',
  },
  {
    id: 3,
    attributeKey: 'embarque',
    attributeDisplayName: 'Embarque',
    attributeDisplayType: 'date',
  },
  {
    id: 4,
    attributeKey: 'canal',
    attributeDisplayName: 'Canal',
    attributeDisplayType: 'list',
    attributeValues: ['Leilão', 'Direto'],
  },
  {
    id: 5,
    attributeKey: 'prioritario',
    attributeDisplayName: 'Prioritário',
    attributeDisplayType: 'checkbox',
  },
];

const CUSTOM_ATTRIBUTES = {
  observacao: 'Lote fechado no leilão',
  cabecas: 30,
  embarque: '2026-03-14',
  canal: 'Leilão',
  prioritario: false,
};

const buildDeal = (overrides = {}) => ({
  id: 1,
  title: 'Fazenda Boa Vista',
  custom_attributes: { ...CUSTOM_ATTRIBUTES },
  ...overrides,
});

const mountAttributes = (deal = buildDeal()) =>
  mount(DealCustomAttributes, { props: { deal } });

const trashButtons = wrapper =>
  wrapper
    .findAllComponents({ name: 'Button' })
    .filter(button => button.props('icon') === 'i-lucide-trash');

describe('DealCustomAttributes.vue', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useCrmBoardStore();
    definitions.value = DEFINITIONS;
  });

  it('names every attribute the account defined for its deals', () => {
    const wrapper = mountAttributes();

    expect(wrapper.text()).toContain('Custom attributes');
    expect(wrapper.text()).toContain('Observação');
    expect(wrapper.text()).toContain('Cabeças');
    expect(wrapper.text()).toContain('Embarque');
    expect(wrapper.text()).toContain('Canal');
    expect(wrapper.text()).toContain('Prioritário');
  });

  it('gives each definition the editor its display type asks for', () => {
    const wrapper = mountAttributes();

    // `text` and `number` fall through to the same inline input editor.
    expect(wrapper.findAllComponents({ name: 'OtherAttribute' })).toHaveLength(
      2
    );
    expect(wrapper.findComponent({ name: 'DateAttribute' }).exists()).toBe(
      true
    );
    expect(wrapper.findComponent({ name: 'ListAttribute' }).exists()).toBe(
      true
    );
    expect(wrapper.findComponent({ name: 'CheckboxAttribute' }).exists()).toBe(
      true
    );
  });

  it('hands each editor the value the deal carries for its key', () => {
    const wrapper = mountAttributes();
    const valueOf = name =>
      wrapper.findComponent({ name }).props('attribute').value;

    expect(wrapper.text()).toContain('Lote fechado no leilão');
    expect(wrapper.text()).toContain('Leilão');
    expect(valueOf('DateAttribute')).toBe('2026-03-14');
    expect(valueOf('CheckboxAttribute')).toBe(false);
  });

  it('leaves an attribute the deal never filled in empty', () => {
    const wrapper = mountAttributes(
      buildDeal({ custom_attributes: { canal: 'Direto' } })
    );

    expect(
      wrapper.findComponent({ name: 'DateAttribute' }).props('attribute').value
    ).toBe('');
    expect(wrapper.text()).toContain('Direto');
  });

  // `custom_attributes` is a single jsonb column, so an update REPLACES the
  // whole map: a payload carrying only the edited key would wipe the rest.
  it('writes the whole map when a single attribute is edited', async () => {
    const updateDeal = vi.spyOn(store, 'updateDeal').mockResolvedValue({});
    const wrapper = mountAttributes();

    await wrapper.get('[role="switch"]').trigger('click');
    await flushPromises();

    expect(updateDeal).toHaveBeenCalledWith(1, {
      custom_attributes: { ...CUSTOM_ATTRIBUTES, prioritario: true },
    });
  });

  it('writes the map without the key when an attribute is removed', async () => {
    const updateDeal = vi.spyOn(store, 'updateDeal').mockResolvedValue({});
    const wrapper = mountAttributes();

    await trashButtons(wrapper)[0].trigger('click');
    await flushPromises();

    const remaining = { ...CUSTOM_ATTRIBUTES };
    delete remaining.observacao;
    expect(updateDeal).toHaveBeenCalledWith(1, {
      custom_attributes: remaining,
    });
  });

  it('picking a value from a list writes it into the whole map', async () => {
    const updateDeal = vi.spyOn(store, 'updateDeal').mockResolvedValue({});
    const wrapper = mountAttributes();

    const list = wrapper.findComponent({ name: 'ListAttribute' });
    list.vm.$emit('update', 'Direto');
    await flushPromises();

    expect(updateDeal).toHaveBeenCalledWith(1, {
      custom_attributes: { ...CUSTOM_ATTRIBUTES, canal: 'Direto' },
    });
  });

  it('says so when the attribute could not be saved', async () => {
    vi.spyOn(store, 'updateDeal').mockRejectedValue(new Error('boom'));
    const wrapper = mountAttributes();

    await wrapper.get('[role="switch"]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Could not save the deal');
  });

  it('renders nothing while the account defines no deal attribute', () => {
    definitions.value = [];
    const wrapper = mountAttributes();

    expect(wrapper.text()).not.toContain('Custom attributes');
    expect(wrapper.find('section').exists()).toBe(false);
  });
});
