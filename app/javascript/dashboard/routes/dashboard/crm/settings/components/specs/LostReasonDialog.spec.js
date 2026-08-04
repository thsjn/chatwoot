import { setActivePinia, createPinia } from 'pinia';
import { mount, flushPromises } from '@vue/test-utils';
import { nextTick } from 'vue';

import { useCrmSettingsStore } from 'dashboard/store/crm/settings';
import LostReasonDialog from '../LostReasonDialog.vue';

vi.mock('dashboard/api/crm/pipelines', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/stages', () => ({
  default: { getStages: vi.fn() },
}));
vi.mock('dashboard/api/crm/sources', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/lostReasons', () => ({
  default: { get: vi.fn(), create: vi.fn(), update: vi.fn() },
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

const EXISTING_REASONS = [
  { id: 55, name: 'Price too high', position: 0, active: true },
  { id: 56, name: 'Bought from a competitor', position: 1, active: true },
];

const mountDialog = () =>
  mount(LostReasonDialog, { global: { stubs: { Dialog: DialogStub } } });

const openWith = async (wrapper, reason = null) => {
  wrapper.vm.open(reason);
  await nextTick();
};

const confirm = wrapper => wrapper.get('[data-testid="confirm"]');

describe('LostReasonDialog.vue', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useCrmSettingsStore();
    store.lostReasons = [...EXISTING_REASONS];
  });

  it('opens blank for a new reason and refuses to save without a name', async () => {
    const wrapper = mountDialog();
    await openWith(wrapper);

    expect(wrapper.text()).toContain('New lost reason');
    expect(confirm(wrapper).attributes('disabled')).toBeDefined();
  });

  it('does not create a reason when it is confirmed blank', async () => {
    const createLostReason = vi
      .spyOn(store, 'createLostReason')
      .mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper);

    // Straight from the dialog, so the guard inside the form is what stops it
    // and not the disabled button.
    wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');
    await flushPromises();

    expect(createLostReason).not.toHaveBeenCalled();
    expect(wrapper.emitted('saved')).toBeUndefined();
  });

  // The picker is ordered by position, so a new reason lands after the ones
  // already offered instead of jumping to the top.
  it('creates the reason at the end of the list, active', async () => {
    const createLostReason = vi
      .spyOn(store, 'createLostReason')
      .mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper);

    await wrapper.get('input[type="text"]').setValue('  No budget  ');

    expect(confirm(wrapper).attributes('disabled')).toBeUndefined();

    await confirm(wrapper).trigger('click');
    await flushPromises();

    expect(createLostReason).toHaveBeenCalledWith({
      name: 'No budget',
      position: 2,
      active: true,
    });
    expect(wrapper.emitted('saved')).toBeTruthy();
  });

  it('opens prefilled for an existing reason and updates it', async () => {
    const updateLostReason = vi
      .spyOn(store, 'updateLostReason')
      .mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper, EXISTING_REASONS[1]);

    expect(wrapper.text()).toContain('Edit lost reason');
    expect(wrapper.get('input[type="text"]').element.value).toBe(
      'Bought from a competitor'
    );

    await wrapper.get('input[type="text"]').setValue('Went to a competitor');
    await confirm(wrapper).trigger('click');
    await flushPromises();

    expect(updateLostReason).toHaveBeenCalledWith(56, {
      name: 'Went to a competitor',
      position: 1,
      active: true,
    });
  });

  // Retiring a reason keeps it on the deals that already carry it, so the form
  // has to be able to save it turned off.
  it('retires a reason by turning it off', async () => {
    const updateLostReason = vi
      .spyOn(store, 'updateLostReason')
      .mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper, EXISTING_REASONS[0]);

    await wrapper.get('[role="switch"]').trigger('click');
    await confirm(wrapper).trigger('click');
    await flushPromises();

    expect(updateLostReason).toHaveBeenCalledWith(
      55,
      expect.objectContaining({ active: false })
    );
  });

  it('sends a cleared position as the top of the list', async () => {
    const createLostReason = vi
      .spyOn(store, 'createLostReason')
      .mockResolvedValue({});
    const wrapper = mountDialog();
    await openWith(wrapper);

    await wrapper.get('input[type="text"]').setValue('No budget');
    await wrapper.get('input[type="number"]').setValue('');
    await confirm(wrapper).trigger('click');
    await flushPromises();

    expect(createLostReason).toHaveBeenCalledWith(
      expect.objectContaining({ position: 0 })
    );
  });
});
