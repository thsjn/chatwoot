class Whatsapp::PhoneInfoService
  # `strict` turns off the "just take the first number" fallbacks. Coexistence onboarding
  # (FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING) returns no phone_number_id at all, so guessing there
  # would silently connect the wrong number. The regular flow keeps the historical lenient behavior.
  def initialize(waba_id, phone_number_id, access_token, strict: false)
    @waba_id = waba_id
    @phone_number_id = phone_number_id
    @access_token = access_token
    @strict = strict
    @api_client = Whatsapp::FacebookApiClient.new(access_token)
  end

  def perform
    validate_parameters!
    fetch_and_process_phone_info
  end

  private

  def validate_parameters!
    raise ArgumentError, 'WABA ID is required' if @waba_id.blank?
    raise ArgumentError, 'Access token is required' if @access_token.blank?
  end

  def fetch_and_process_phone_info
    response = @api_client.fetch_phone_numbers(@waba_id)
    phone_numbers = response['data']

    phone_data = find_phone_data(phone_numbers)
    raise "No phone numbers found for WABA #{@waba_id}" if phone_data.nil?

    build_phone_info(phone_data)
  end

  def find_phone_data(phone_numbers)
    return nil if phone_numbers.blank?
    return find_phone_data_strict(phone_numbers) if @strict
    return phone_numbers.find { |phone| phone['id'] == @phone_number_id } || phone_numbers.first if @phone_number_id.present?

    phone_numbers.first
  end

  # Strict mode never guesses: without an id the WABA must hold exactly one number, and an id that
  # matches nothing is an error instead of a silent fallback to the first number.
  def find_phone_data_strict(phone_numbers)
    phone_data = if @phone_number_id.present?
                   phone_numbers.find { |phone| phone['id'] == @phone_number_id }
                 elsif phone_numbers.one?
                   phone_numbers.first
                 end

    raise undetermined_phone_number_error(phone_numbers.size) if phone_data.nil?

    phone_data
  end

  def undetermined_phone_number_error(phone_numbers_count)
    "Unable to automatically determine the phone number to connect for WABA #{@waba_id}: #{phone_numbers_count} phone number(s) " \
      'found on the WhatsApp Business Account. Inform the phone number explicitly and try again.'
  end

  def build_phone_info(phone_data)
    display_phone_number = sanitize_phone_number(phone_data['display_phone_number'])

    {
      phone_number_id: phone_data['id'],
      phone_number: "+#{display_phone_number}",
      verified: phone_data['code_verification_status'] == 'VERIFIED',
      business_name: phone_data['verified_name'] || phone_data['display_phone_number']
    }
  end

  def sanitize_phone_number(phone_number)
    return phone_number if phone_number.blank?

    phone_number.gsub(/[\s\-\(\)\.\+]/, '').strip
  end
end
