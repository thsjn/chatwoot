import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import Reauthorize from '../Reauthorize.vue';
import whatsappChannel from 'dashboard/api/channel/whatsappChannel';

const mockUseAlert = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => mockUseAlert(...args),
}));

vi.mock('dashboard/api/channel/whatsappChannel', () => ({
  default: { postEmbeddedSignupAuthorization: vi.fn() },
}));

vi.mock('vue-i18n', async () => {
  const actual = await vi.importActual('vue-i18n');
  return {
    ...actual,
    useI18n: () => ({ t: key => key }),
  };
});

// Everything except isValidBusinessData is faked so the test can drive the
// postMessage callback directly without the real FB SDK/popup plumbing.
// isValidBusinessData is left as the real implementation (already unit
// tested on its own in specs/utils.spec.js) so the payload-shaping
// assertions below exercise real validation, not a re-implemented mock.
let signupCallback;
vi.mock('../utils', async () => {
  const actual = await vi.importActual('../utils');
  return {
    ...actual,
    setupFacebookSdk: vi.fn().mockResolvedValue(),
    initWhatsAppEmbeddedSignup: vi.fn(),
    createMessageHandler: vi.fn(callback => {
      signupCallback = callback;
      return () => {};
    }),
  };
});

import { initWhatsAppEmbeddedSignup } from '../utils';

let originalChatwootConfig;

const mountReauthorize = (overrides = {}) => {
  window.chatwootConfig = {
    whatsappAppId: 'app-id',
    whatsappConfigurationId: 'config-id',
    whatsappApiVersion: 'v22.0',
  };

  return mount(Reauthorize, {
    props: {
      inbox: { id: 42, provider_config: {}, ...overrides },
    },
  });
};

describe('Reauthorize.vue', () => {
  beforeEach(() => {
    originalChatwootConfig = window.chatwootConfig;
    vi.clearAllMocks();
    signupCallback = undefined;
    whatsappChannel.postEmbeddedSignupAuthorization.mockResolvedValue({
      data: { success: true },
    });
  });

  afterEach(() => {
    window.chatwootConfig = originalChatwootConfig;
  });

  const triggerAuthorization = async wrapper => {
    // onMounted awaits setupFacebookSdk before isLoadingFacebook flips to
    // false; requestAuthorization no-ops (with a "loading" alert) until
    // then, so flush that first.
    await Promise.resolve();
    await Promise.resolve();

    // requestAuthorization is exposed via defineExpose for the parent to
    // call; InboxReconnectionRequired's @reauthorize just forwards to it.
    await wrapper.vm.requestAuthorization();
    // Let handleLoginAndReauthorize's initWhatsAppEmbeddedSignup promise
    // settle.
    await Promise.resolve();
    await Promise.resolve();
  };

  it('builds a coexistence payload without phone_number_id for a FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING event', async () => {
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');
    const wrapper = mountReauthorize();
    await triggerAuthorization(wrapper);

    expect(signupCallback).toBeInstanceOf(Function);
    await signupCallback({
      event: 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING',
      data: { waba_id: 'waba-1' },
    });

    expect(
      whatsappChannel.postEmbeddedSignupAuthorization
    ).toHaveBeenCalledTimes(1);
    const payload =
      whatsappChannel.postEmbeddedSignupAuthorization.mock.calls[0][0];
    expect(payload).toEqual({
      inboxId: 42,
      code: 'auth-code',
      business_id: undefined,
      waba_id: 'waba-1',
      coexistence: true,
    });
    expect(payload).not.toHaveProperty('phone_number_id');
  });

  it('builds the normal payload for a FINISH event, without a coexistence flag', async () => {
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');
    const wrapper = mountReauthorize();
    await triggerAuthorization(wrapper);

    await signupCallback({
      event: 'FINISH',
      data: {
        business_id: 'biz-1',
        waba_id: 'waba-1',
        phone_number_id: 'phone-1',
      },
    });

    expect(
      whatsappChannel.postEmbeddedSignupAuthorization
    ).toHaveBeenCalledTimes(1);
    const payload =
      whatsappChannel.postEmbeddedSignupAuthorization.mock.calls[0][0];
    expect(payload).toEqual({
      inboxId: 42,
      code: 'auth-code',
      business_id: 'biz-1',
      waba_id: 'waba-1',
      phone_number_id: 'phone-1',
    });
    expect(payload).not.toHaveProperty('coexistence');
  });

  it('shows a cancelled alert and does not call the API on a CANCEL event', async () => {
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');
    const wrapper = mountReauthorize();
    await triggerAuthorization(wrapper);

    await signupCallback({ event: 'CANCEL' });

    expect(
      whatsappChannel.postEmbeddedSignupAuthorization
    ).not.toHaveBeenCalled();
    expect(mockUseAlert).toHaveBeenCalledWith(
      'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.CANCELLED'
    );
  });

  it('shows the Meta error message and does not call the API on an error event', async () => {
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');
    const wrapper = mountReauthorize();
    await triggerAuthorization(wrapper);

    await signupCallback({
      event: 'error',
      error_message: 'WABA not eligible',
    });

    expect(
      whatsappChannel.postEmbeddedSignupAuthorization
    ).not.toHaveBeenCalled();
    expect(mockUseAlert).toHaveBeenCalledWith('WABA not eligible');
  });
});
