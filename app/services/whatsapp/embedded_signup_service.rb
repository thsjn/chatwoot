class Whatsapp::EmbeddedSignupService
  def initialize(account:, params:, inbox_id: nil)
    @account = account
    @code = params[:code]
    @waba_id = params[:waba_id]
    @phone_number_id = params[:phone_number_id]
    # Coexistence onboarding (FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING) returns neither
    # `business_id` nor `phone_number_id`, so the flag is what tells the flows apart.
    @coexistence = ActiveModel::Type::Boolean.new.cast(params[:coexistence]) || false
    @inbox_id = inbox_id
  end

  def perform
    validate_parameters!

    access_token = exchange_code_for_token
    phone_info = fetch_phone_info(access_token)

    channel = create_or_reauthorize_channel(access_token, phone_info)
    # NOTE: We call setup_webhooks explicitly here instead of relying on after_commit callback because:
    # 1. Reauthorization flow updates an existing channel (not a create), so after_commit on: :create won't trigger
    # 2. We need to run check_channel_health_and_prompt_reauth after webhook setup completes
    # 3. The channel is marked with source: 'embedded_signup' to skip the after_commit callback
    channel.setup_webhooks
    # Skip health check during reauthorization — phone numbers in pending provisioning state
    # (platform_type: NOT_APPLICABLE) would incorrectly trigger a disconnect email right after
    # a successful reauth. Only run health check for new channel creation.
    check_channel_health_and_prompt_reauth(channel) if @inbox_id.blank?
    channel

  rescue StandardError => e
    Rails.logger.error("[WHATSAPP] Embedded signup failed: #{e.message}")
    raise e
  end

  private

  def exchange_code_for_token
    Whatsapp::TokenExchangeService.new(@code).perform
  end

  def fetch_phone_info(access_token)
    Whatsapp::PhoneInfoService.new(@waba_id, resolved_phone_number_id, access_token, strict: @coexistence).perform
  end

  # Reauth/reconfiguration popups frequently post an empty phone_number_id. When the inbox already
  # exists, its persisted config knows exactly which number it is bound to, so use that instead of
  # making the WABA lookup resolve the number on its own.
  def resolved_phone_number_id
    @resolved_phone_number_id ||= @phone_number_id.presence || persisted_phone_number_id
  end

  def persisted_phone_number_id
    channel = existing_channel
    return unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'

    channel.provider_config['phone_number_id'].presence
  end

  def existing_channel
    return if @inbox_id.blank?

    @existing_channel ||= @account.inboxes.find(@inbox_id).channel
  end

  def create_or_reauthorize_channel(access_token, phone_info)
    if @inbox_id.present?
      channel = existing_channel
      if channel.provider == 'whatsapp_cloud'
        Whatsapp::ReauthorizationService.new(
          account: @account,
          inbox_id: @inbox_id,
          phone_number_id: @phone_number_id,
          waba_id: @waba_id,
          coexistence: @coexistence
        ).perform(access_token, phone_info)
      else
        convert_channel_to_cloud(channel, access_token, phone_info)
      end
    else
      waba_info = { waba_id: @waba_id, business_name: phone_info[:business_name] }
      Whatsapp::ChannelCreationService.new(@account, waba_info, phone_info, access_token, coexistence: @coexistence).perform
    end
  end

  def convert_channel_to_cloud(channel, access_token, phone_info)
    new_provider_config = {
      'api_key' => access_token,
      # Coexistence onboarding does not return a phone_number_id; fall back to the one resolved from the WABA.
      'phone_number_id' => @phone_number_id.presence || phone_info[:phone_number_id],
      'business_account_id' => @waba_id,
      'source' => 'embedded_signup'
    }
    new_provider_config['coexistence'] = true if @coexistence

    channel.convert_provider!(new_provider: 'whatsapp_cloud', new_provider_config: new_provider_config)
    channel
  end

  def check_channel_health_and_prompt_reauth(channel)
    health_data = Whatsapp::HealthService.new(channel).fetch_health_status
    return unless health_data

    if channel_in_pending_state?(health_data)
      channel.prompt_reauthorization!
    else
      Rails.logger.info "[WHATSAPP] Channel #{channel.phone_number} health check passed"
    end
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Health check failed for channel #{channel.phone_number}: #{e.message}"
  end

  def channel_in_pending_state?(health_data)
    health_data[:platform_type] == 'NOT_APPLICABLE' ||
      health_data.dig(:throughput, 'level') == 'NOT_APPLICABLE'
  end

  # `business_id` is intentionally not required: the coexistence flow
  # (FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING) only returns `waba_id`.
  def validate_parameters!
    missing_params = []
    missing_params << 'code' if @code.blank?
    missing_params << 'waba_id' if @waba_id.blank?

    return if missing_params.empty?

    raise ArgumentError, "Required parameters are missing: #{missing_params.join(', ')}"
  end
end
