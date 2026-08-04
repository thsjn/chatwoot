import { setActivePinia, createPinia } from 'pinia';
import { mount, flushPromises } from '@vue/test-utils';
import { nextTick } from 'vue';

import { useCrmSettingsStore } from 'dashboard/store/crm/settings';
import StageDialog from '../StageDialog.vue';

vi.mock('dashboard/api/crm/pipelines', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/stages', () => ({
  default: {
    getStages: vi.fn(),
    createStage: vi.fn(),
    updateStage: vi.fn(),
    deleteStage: vi.fn(),
  },
}));
vi.mock('dashboard/api/crm/sources', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/lostReasons', () => ({
  default: { get: vi.fn() },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

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

const EXISTING_STAGE = {
  id: 5,
  name: 'Negotiation',
  category: 'open',
  color: 'amber',
  probability: 40,
  rotting_days: 3,
  wip_limit: 7,
  is_entry: false,
};

const mountDialog = () =>
  mount(StageDialog, {
    props: { pipelineId: 1 },
    global: { stubs: { Dialog: DialogStub } },
  });

const openWith = async (wrapper, stage = null) => {
  wrapper.vm.open(stage);
  await nextTick();
};

describe('StageDialog.vue', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useCrmSettingsStore();
    store.stages = [EXISTING_STAGE, { ...EXISTING_STAGE, id: 6 }];
  });

  it('opens blank for a new stage and refuses to save without a name', async () => {
    const wrapper = mountDialog();
    await openWith(wrapper);

    expect(wrapper.text()).toContain('New stage');
    expect(
      wrapper.get('[data-testid="confirm"]').attributes('disabled')
    ).toBeDefined();
  });

  it('does not create a stage when it is confirmed blank', async () => {
    const createStage = vi.spyOn(store, 'createStage').mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper);

    // Straight from the dialog, so the guard inside the form is what stops it
    // and not the disabled button.
    wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');
    await flushPromises();

    expect(createStage).not.toHaveBeenCalled();
    expect(wrapper.emitted('saved')).toBeUndefined();
  });

  it('creates the stage at the end of the pipeline', async () => {
    const createStage = vi.spyOn(store, 'createStage').mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper);

    await wrapper.get('input').setValue('  Discovery  ');

    expect(
      wrapper.get('[data-testid="confirm"]').attributes('disabled')
    ).toBeUndefined();

    await wrapper.get('[data-testid="confirm"]').trigger('click');
    await flushPromises();

    // The two optional limits were left blank, and the backend only accepts
    // them as "a number above zero, or nothing at all".
    expect(createStage).toHaveBeenCalledWith(1, {
      name: 'Discovery',
      category: 'open',
      color: 'slate',
      probability: 0,
      rotting_days: null,
      wip_limit: null,
      is_entry: false,
      position: 2,
    });
    expect(wrapper.emitted('saved')).toBeTruthy();
  });

  it('opens prefilled for an existing stage and updates it', async () => {
    const updateStage = vi.spyOn(store, 'updateStage').mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper, EXISTING_STAGE);

    expect(wrapper.text()).toContain('Edit stage');
    expect(wrapper.get('input').element.value).toBe('Negotiation');

    await wrapper.get('input').setValue('Negotiation II');
    await wrapper.get('[data-testid="confirm"]').trigger('click');
    await flushPromises();

    expect(updateStage).toHaveBeenCalledWith(
      1,
      5,
      expect.objectContaining({
        name: 'Negotiation II',
        category: 'open',
        color: 'amber',
        probability: 40,
        rotting_days: 3,
        wip_limit: 7,
      })
    );
  });

  it('sends a discarded optional limit as null instead of zero', async () => {
    const updateStage = vi.spyOn(store, 'updateStage').mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper, EXISTING_STAGE);

    const numberInputs = wrapper.findAll('input[type="number"]');
    await numberInputs[1].setValue('');
    await numberInputs[2].setValue('');
    await wrapper.get('[data-testid="confirm"]').trigger('click');
    await flushPromises();

    expect(updateStage).toHaveBeenCalledWith(
      1,
      5,
      expect.objectContaining({ rotting_days: null, wip_limit: null })
    );
  });
});