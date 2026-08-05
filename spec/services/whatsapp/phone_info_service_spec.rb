require 'rails_helper'

describe Whatsapp::PhoneInfoService do
  let(:waba_id) { 'test_waba_id' }
  let(:phone_number_id) { 'test_phone_number_id' }
  let(:access_token) { 'test_access_token' }
  let(:service) { described_class.new(waba_id, phone_number_id, access_token) }
  let(:api_client) { instance_double(Whatsapp::FacebookApiClient) }

  before do
    allow(Whatsapp::FacebookApiClient).to receive(:new).with(access_token).and_return(api_client)
  end

  describe '#perform' do
    let(:multi_number_response) do
      {
        'data' => [
          {
            'id' => 'first_phone_id',
            'display_phone_number' => '1234567890',
            'verified_name' => 'Test Business',
            'code_verification_status' => 'VERIFIED'
          },
          {
            'id' => 'second_phone_id',
            'display_phone_number' => '9876543210',
            'verified_name' => 'Other Business',
            'code_verification_status' => 'VERIFIED'
          }
        ]
      }
    end
    let(:phone_response) do
      {
        'data' => [
          {
            'id' => phone_number_id,
            'display_phone_number' => '1234567890',
            'verified_name' => 'Test Business',
            'code_verification_status' => 'VERIFIED'
          }
        ]
      }
    end

    context 'when all parameters are valid' do
      before do
        allow(api_client).to receive(:fetch_phone_numbers).with(waba_id).and_return(phone_response)
      end

      it 'returns formatted phone info' do
        result = service.perform
        expect(result).to eq({
                               phone_number_id: phone_number_id,
                               phone_number: '+1234567890',
                               verified: true,
                               business_name: 'Test Business'
                             })
      end
    end

    context 'when phone_number_id is not provided' do
      let(:phone_number_id) { nil }
      let(:phone_response) do
        {
          'data' => [
            {
              'id' => 'first_phone_id',
              'display_phone_number' => '1234567890',
              'verified_name' => 'Test Business',
              'code_verification_status' => 'VERIFIED'
            }
          ]
        }
      end

      before do
        allow(api_client).to receive(:fetch_phone_numbers).with(waba_id).and_return(phone_response)
      end

      it 'uses the only available phone number' do
        result = service.perform
        expect(result[:phone_number_id]).to eq('first_phone_id')
      end
    end

    context 'when phone_number_id is not provided and the WABA has multiple phone numbers' do
      let(:phone_number_id) { nil }
      let(:phone_response) { multi_number_response }

      before do
        allow(api_client).to receive(:fetch_phone_numbers).with(waba_id).and_return(phone_response)
      end

      # Meta often omits the phone_number_id on the regular flow, so the lenient default must stay.
      it 'falls back to the first phone number' do
        result = service.perform
        expect(result[:phone_number_id]).to eq('first_phone_id')
      end
    end

    # Strict mode is used by coexistence onboarding, where the popup has no phone number selector,
    # so silently connecting the wrong number would be worse than failing.
    context 'when strict mode is enabled' do
      let(:service) { described_class.new(waba_id, phone_number_id, access_token, strict: true) }

      before do
        allow(api_client).to receive(:fetch_phone_numbers).with(waba_id).and_return(phone_response)
      end

      context 'when phone_number_id is absent and the WABA has a single phone number' do
        let(:phone_number_id) { nil }
        let(:phone_response) do
          {
            'data' => [
              {
                'id' => 'only_phone_id',
                'display_phone_number' => '1234567890',
                'verified_name' => 'Test Business',
                'code_verification_status' => 'VERIFIED'
              }
            ]
          }
        end

        it 'uses the only available phone number' do
          result = service.perform
          expect(result[:phone_number_id]).to eq('only_phone_id')
        end
      end

      context 'when phone_number_id is absent and the WABA has multiple phone numbers' do
        let(:phone_number_id) { nil }
        let(:phone_response) { multi_number_response }

        it 'raises an actionable error instead of guessing' do
          expect { service.perform }.to raise_error(
            /Unable to automatically determine the phone number to connect for WABA #{waba_id}: 2 phone number\(s\) found/
          )
        end
      end

      context 'when phone_number_id does not match any phone number on the WABA' do
        let(:phone_number_id) { 'unknown_phone_id' }
        let(:phone_response) { multi_number_response }

        it 'raises instead of falling back to the first phone number' do
          expect { service.perform }.to raise_error(/Unable to automatically determine the phone number to connect for WABA/)
        end
      end
    end

    context 'when specific phone_number_id is not found' do
      let(:phone_number_id) { 'different_id' }
      let(:phone_response) do
        {
          'data' => [
            {
              'id' => 'available_phone_id',
              'display_phone_number' => '9876543210',
              'verified_name' => 'Different Business',
              'code_verification_status' => 'VERIFIED'
            }
          ]
        }
      end

      before do
        allow(api_client).to receive(:fetch_phone_numbers).with(waba_id).and_return(phone_response)
      end

      it 'uses the first available phone number as fallback' do
        result = service.perform
        expect(result[:phone_number_id]).to eq('available_phone_id')
        expect(result[:phone_number]).to eq('+9876543210')
      end
    end

    context 'when no phone numbers are available' do
      let(:phone_response) { { 'data' => [] } }

      before do
        allow(api_client).to receive(:fetch_phone_numbers).with(waba_id).and_return(phone_response)
      end

      it 'raises an error' do
        expect { service.perform }.to raise_error(/No phone numbers found for WABA/)
      end
    end

    context 'when waba_id is blank' do
      let(:waba_id) { '' }

      it 'raises ArgumentError' do
        expect { service.perform }.to raise_error(ArgumentError, 'WABA ID is required')
      end
    end

    context 'when access_token is blank' do
      let(:access_token) { '' }

      it 'raises ArgumentError' do
        expect { service.perform }.to raise_error(ArgumentError, 'Access token is required')
      end
    end

    context 'when phone number has special characters' do
      let(:phone_response) do
        {
          'data' => [
            {
              'id' => phone_number_id,
              'display_phone_number' => '+1 (234) 567-8900',
              'verified_name' => 'Test Business',
              'code_verification_status' => 'VERIFIED'
            }
          ]
        }
      end

      before do
        allow(api_client).to receive(:fetch_phone_numbers).with(waba_id).and_return(phone_response)
      end

      it 'sanitizes the phone number' do
        result = service.perform
        expect(result[:phone_number]).to eq('+12345678900')
      end
    end
  end
end
