require 'rails_helper'

RSpec.describe 'CRM external lead ingestion API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:pipeline) do
    create(:crm_pipeline, :default, account: account,
                                    settings: { 'inbox_ids' => [], 'janela_dedupe_dias' => 30, 'moeda_padrao' => 'BRL' })
  end
  let!(:entry_stage) { create(:crm_stage, :entry, account: account, pipeline: pipeline, position: 1000) }
  let(:source) { create(:crm_source, account: account, kind: :api, name: 'Landing arroba', inbox: inbox) }
  let!(:token) { source.regenerate_token! }

  let(:url) { "/public/api/v1/accounts/#{account.id}/crm/leads" }
  let(:payload) { { name: 'Maria Souza', email: 'maria@exemplo.com', title: 'Lote de novilhas', value: 45_000.0 } }
  let(:headers) { { 'X-Crm-Source-Token' => token } }

  describe 'when the account has the CRM module disabled' do
    before { account.update!(crm_kanban: false) }

    # 404 and not 401: with the module off the endpoint does not exist, so a valid token cannot be
    # used to tell an account that never enabled the CRM apart from one that is not there.
    it 'refuses the lead even with a valid token' do
      expect { post url, params: payload, headers: headers, as: :json }.not_to change(Crm::Deal, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'authentication' do
    it 'refuses a request with no token' do
      expect { post url, params: payload, as: :json }.not_to change(Crm::Deal, :count)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses an unknown token' do
      expect do
        post url, params: payload, headers: { 'X-Crm-Source-Token' => 'nope' }, as: :json
      end.not_to change(Crm::Deal, :count)

      expect(response).to have_http_status(:unauthorized)
    end

    # The token is resolved INSIDE the account of the URL, so a perfectly valid credential of
    # another account is indistinguishable from a made up one.
    it 'refuses a valid token that belongs to another account' do
      foreign_source = create(:crm_source, account: other_account, kind: :api, inbox: create(:inbox, account: other_account))
      foreign_token = foreign_source.regenerate_token!

      expect do
        post url, params: payload, headers: { 'X-Crm-Source-Token' => foreign_token }, as: :json
      end.not_to change(Crm::Deal, :count)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses the token of a source that was turned off' do
      source.update!(active: false)

      post url, params: payload, headers: headers, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses a token that was replaced by a new one' do
      source.regenerate_token!

      post url, params: payload, headers: headers, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'accepts the token through the Authorization bearer header' do
      post url, params: payload, headers: { 'Authorization' => "Bearer #{token}" }, as: :json

      expect(response).to have_http_status(:created)
    end

    it 'never requires a user session' do
      post url, params: payload, headers: headers, as: :json

      expect(response).to have_http_status(:created)
    end
  end

  describe 'creating the deal' do
    it 'opens a card in the entry stage of the default pipeline' do
      expect { post url, params: payload, headers: headers, as: :json }.to change(Crm::Deal, :count).by(1)

      expect(response).to have_http_status(:created)
      deal = Crm::Deal.last
      expect(response.parsed_body).to include('deal_id' => deal.id, 'status' => 'created')
      expect(deal.pipeline).to eq(pipeline)
      expect(deal.stage).to eq(entry_stage)
    end

    it 'fills the card from the payload and tags it with the source' do
      post url, params: payload, headers: headers, as: :json

      deal = Crm::Deal.last
      expect(deal.title).to eq('Lote de novilhas')
      expect(deal.value_cents).to eq(4_500_000)
      expect(deal.currency).to eq('BRL')
      expect(deal.source).to eq(source)
      expect(deal.source_inbox_id).to eq(inbox.id)
    end

    it 'creates the contact from the payload' do
      expect { post url, params: payload, headers: headers, as: :json }.to change(Contact, :count).by(1)

      contact = Crm::Deal.last.contact
      expect(contact.email).to eq('maria@exemplo.com')
      expect(contact.name).to eq('Maria Souza')
    end

    it 'registers the contact in the inbox of the source' do
      post url, params: payload, headers: headers, as: :json

      contact = Crm::Deal.last.contact
      expect(contact.contact_inboxes.pluck(:inbox_id)).to include(inbox.id)
    end

    it 'reuses a contact the account already knows' do
      contact = create(:contact, account: account, email: 'maria@exemplo.com')

      expect { post url, params: payload, headers: headers, as: :json }.not_to change(Contact, :count)

      expect(Crm::Deal.last.contact_id).to eq(contact.id)
    end

    it 'accepts a lead identified only by phone number' do
      post url, params: { name: 'João', phone_number: '+5533999999999' }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(Crm::Deal.last.contact.phone_number).to eq('+5533999999999')
    end

    it 'falls back to the contact name when no title is given' do
      post url, params: { name: 'Maria Souza', email: 'maria@exemplo.com' }, headers: headers, as: :json

      expect(Crm::Deal.last.title).to eq('Maria Souza')
    end

    it 'stores only the standard campaign parameters' do
      post url, params: payload.merge(utm: { utm_source: 'google', utm_campaign: 'verao', owner_id: 99 }),
                headers: headers, as: :json

      expect(Crm::Deal.last.utm).to eq({ 'utm_source' => 'google', 'utm_campaign' => 'verao' })
    end

    # A public endpoint must not be able to hand a card to an agent or drop it straight into a
    # won column: everything outside the permitted list is dropped.
    it 'ignores attributes the caller is not allowed to set' do
      agent = create(:user, account: account, role: :agent)
      won_stage = create(:crm_stage, :won, account: account, pipeline: pipeline, position: 2000)

      post url, params: payload.merge(owner_id: agent.id, stage_id: won_stage.id, status: 'won'), headers: headers, as: :json

      deal = Crm::Deal.last
      expect(deal.owner_id).to be_nil
      expect(deal.stage).to eq(entry_stage)
      expect(deal.status).to eq('open')
    end

    it 'targets an explicit pipeline of the account' do
      other_pipeline = create(:crm_pipeline, account: account, name: 'Pós-venda')
      other_entry = create(:crm_stage, :entry, account: account, pipeline: other_pipeline, position: 1000)

      post url, params: payload.merge(pipeline_id: other_pipeline.id), headers: headers, as: :json

      expect(Crm::Deal.last.stage).to eq(other_entry)
    end

    it 'refuses a pipeline of another account' do
      foreign_pipeline = create(:crm_pipeline, account: other_account)

      expect do
        post url, params: payload.merge(pipeline_id: foreign_pipeline.id), headers: headers, as: :json
      end.not_to change(Crm::Deal, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('pipeline_not_found')
    end
  end

  describe 'payload validation' do
    it 'refuses a lead with no email and no phone number' do
      expect do
        post url, params: { name: 'Anônimo' }, headers: headers, as: :json
      end.not_to change(Crm::Deal, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('contact_required')
    end

    it 'refuses a malformed email' do
      post url, params: { name: 'Maria', email: 'not-an-email' }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'refuses a source with no inbox to register the contact in' do
      source.update!(inbox: nil)

      post url, params: payload, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('source_without_inbox')
    end
  end

  describe 'deduplication' do
    it 'links a repeated lead to the card the contact already has' do
      post url, params: payload, headers: headers, as: :json
      deal_id = response.parsed_body['deal_id']

      expect { post url, params: payload, headers: headers, as: :json }.not_to change(Crm::Deal, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('deal_id' => deal_id, 'status' => 'deduplicated')
    end

    it 'opens a new card once the dedupe window has passed' do
      post url, params: payload, headers: headers, as: :json
      Crm::Deal.last.update_columns(created_at: 40.days.ago, updated_at: 40.days.ago)

      expect { post url, params: payload, headers: headers, as: :json }.to change(Crm::Deal, :count).by(1)
    end

    it 'opens a new card when the previous one is already closed' do
      post url, params: payload, headers: headers, as: :json
      Crm::Deal.last.update!(status: :won)

      expect { post url, params: payload, headers: headers, as: :json }.to change(Crm::Deal, :count).by(1)
    end
  end

  describe 'archived pipelines' do
    it 'refuses the lead when the only pipeline is archived' do
      pipeline.archive!

      expect { post url, params: payload, headers: headers, as: :json }.not_to change(Crm::Deal, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('pipeline_not_found')
    end

    it 'refuses an archived pipeline even when it is asked for by id' do
      pipeline.archive!
      active_pipeline = create(:crm_pipeline, account: account, name: 'Ativo')
      create(:crm_stage, :entry, account: account, pipeline: active_pipeline, position: 1000)

      post url, params: payload.merge(pipeline_id: pipeline.id), headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('pipeline_not_found')
    end

    it 'falls back to an active pipeline when the default one was retired' do
      pipeline.archive!
      active_pipeline = create(:crm_pipeline, account: account, name: 'Ativo')
      active_entry = create(:crm_stage, :entry, account: account, pipeline: active_pipeline, position: 1000)

      post url, params: payload, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(Crm::Deal.last.stage).to eq(active_entry)
    end
  end

  # The IP safelist of Rack::Attack covers 127.0.0.1, which is where request specs come from, so the
  # throttle only engages for a request that looks like it came from outside.
  #
  # Rack::Attack itself is switched off outside production (see config/initializers/rack_attack.rb),
  # so exercising the throttle for real means flipping it on for the duration of these examples and
  # restoring whatever was there before, whether the example passes or raises.
  describe 'rate limiting' do
    let(:throttle) { Rack::Attack.throttles['/public/api/v1/accounts/:account_id/crm/leads'] }
    let(:remote_headers) { headers.merge('REMOTE_ADDR' => '203.0.113.10') }

    around do |example|
      original_enabled = Rack::Attack.enabled
      Rack::Attack.enabled = true
      example.run
    ensure
      Rack::Attack.enabled = original_enabled
    end

    before { allow(throttle).to receive(:limit).and_return(1) }

    it 'throttles the source once its budget is spent' do
      post url, params: payload, headers: remote_headers, as: :json
      expect(response).to have_http_status(:created)

      expect do
        post url, params: payload, headers: remote_headers, as: :json
      end.not_to change(Crm::Deal, :count)

      expect(response).to have_http_status(:too_many_requests)
    end

    # The budget is per credential, not per IP: one noisy landing page must not be able to starve
    # the n8n flow of the same account.
    it 'gives each source its own budget' do
      other_source = create(:crm_source, account: account, kind: :n8n, name: 'n8n', inbox: inbox)
      other_token = other_source.regenerate_token!

      post url, params: payload, headers: remote_headers, as: :json
      expect(response).to have_http_status(:created)

      post url, params: { name: 'João', phone_number: '+5533988888888' },
                headers: remote_headers.merge('X-Crm-Source-Token' => other_token), as: :json

      expect(response).to have_http_status(:created)
    end
  end
end
