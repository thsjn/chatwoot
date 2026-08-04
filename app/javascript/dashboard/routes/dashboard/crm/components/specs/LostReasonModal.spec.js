import { setActivePinia, createPinia } from 'pinia';
import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';

import { useCrmBoardStore } from 'dashboard/store/crm/board';
import LostReasonModal from '../LostReasonModal.vue';

vi.mock('dashboard/api/crm/deals', () => ({
  default: { get: vi.fn(), move: vi.fn() },
}));
vi.mock('dashboard/api/crm/pipelines', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/crm/stages', () => ({
  default: { getStages: vi.fn() },
}));
vi.mock('dashboard/api/crm/lostReasons', () => ({
  default: { get: vi.fn() },
}));
vi.mock('dashboard/api/crm/sources', () => ({ default: { get: vi.fn() } }));

const PENDING_MOVE = { dealId: 1, stageId: 20, targetIndex: 0 };

// `<dialog>.showModal()` is not implemented in jsdom, so the dialog is doubled
// by its contract: it renders its content while open, exposes open/close and
// answers the two buttons the modal is wired to.
const DialogStub = {
  name: 'Dialog',
  props: {
    title: { type: String, default: '' },
    confirmButtonLabel: { type: String, default: '' },
    cancelButtonLabel: { type: String, default: '' },
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
      <button data-testid="cancel" @click="close">
        {{ cancelButtonLabel }}
      </button>
      <button
        data-testid="confirm"
        :disabled="disableConfirmButton"
        @click="$emit('confirm')"
      >
        {{ confirmButtonLabel }}
      </button>
    </div>
  `,
};

const mountModal = () =>
  mount(LostReasonModal, { global: { stubs: { Dialog: DialogStub } } });

describe('LostReasonModal.vue', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useCrmBoardStore();
    store.lostReasons = [
      { id: 55, name: 'Price too high' },
      { id: 56, name: 'Bought from a competitor' },
    ];
  });

  it('stays closed while no move is waiting for a reason', () => {
    const wrapper = mountModal();

    expect(wrapper.find('[data-testid="dialog"]').exists()).toBe(false);
  });

  it('opens listing the reasons once a move is pending', async () => {
    const wrapper = mountModal();

    store.pendingLostReasonMove = { ...PENDING_MOVE };
    await nextTick();

    expect(wrapper.text()).toContain('Mark deal as lost');
    expect(wrapper.text()).toContain('Price too high');
    expect(wrapper.text()).toContain('Bought from a competitor');
  });

  it('closes again once the pending move is released', async () => {
    const wrapper = mountModal();

    store.pendingLostReasonMove = { ...PENDING_MOVE };
    await nextTick();
    store.pendingLostReasonMove = null;
    await nextTick();

    expect(wrapper.find('[data-testid="dialog"]').exists()).toBe(false);
  });

  it('refuses to confirm before a reason is picked', async () => {
    const wrapper = mountModal();

    store.pendingLostReasonMove = { ...PENDING_MOVE };
    await nextTick();

    expect(
      wrapper.get('[data-testid="confirm"]').attributes('disabled')
    ).toBeDefined();
  });

  it('confirms the move with the reason that was picked', async () => {
    const confirmLostReason = vi
      .spyOn(store, 'confirmLostReason')
      .mockResolvedValue({ success: true });
    const wrapper = mountModal();

    store.pendingLostReasonMove = { ...PENDING_MOVE };
    await nextTick();
    await wrapper.get('select').setValue('56');
    await wrapper.get('[data-testid="confirm"]').trigger('click');

    expect(confirmLostReason).toHaveBeenCalledWith(56);
  });

  it('drops the pending move when the dialog is cancelled', async () => {
    const wrapper = mountModal();

    store.pendingLostReasonMove = { ...PENDING_MOVE };
    store.moveError = {
      code: 'lost_reason_required',
      messageKey: 'CRM.MOVE.LOST_REASON_REQUIRED',
    };
    await nextTick();
    await wrapper.get('[data-testid="cancel"]').trigger('click');

    expect(store.pendingLostReasonMove).toBeNull();
    expect(store.moveError).toBeNull();
  });

  it('explains a reason that was retired and clears the dead selection', async () => {
    const wrapper = mountModal();

    store.pendingLostReasonMove = { ...PENDING_MOVE };
    await nextTick();
    await wrapper.get('select').setValue('55');

    store.moveError = {
      code: 'lost_reason_inactive',
      messageKey: 'CRM.MOVE.LOST_REASON_INACTIVE',
    };
    await nextTick();

    expect(wrapper.text()).toContain(
      'That lost reason is no longer available.'
    );
    // The retired reason left the picker, so the selection it left behind
    // cannot be confirmed again.
    expect(
      wrapper.get('[data-testid="confirm"]').attributes('disabled')
    ).toBeDefined();
  });

  it('keeps quiet about the failure that opened it', async () => {
    const wrapper = mountModal();

    store.pendingLostReasonMove = { ...PENDING_MOVE };
    store.moveError = {
      code: 'lost_reason_required',
      messageKey: 'CRM.MOVE.LOST_REASON_REQUIRED',
    };
    await nextTick();

    expect(wrapper.text()).not.toContain('Lost reason is required');
  });
});