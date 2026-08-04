require 'rails_helper'

# Guard against N+1 regressions on the two listings that grow with the account: the board column
# (25 cards, each rendering a contact, an owner, an inbox and an avatar) and the deal timeline.
#
# The assertion is on the NUMBER OF QUERIES and never on time: the point is that the listing keeps
# costing the same as the volume grows, which is exactly what a reintroduced N+1 breaks.
RSpec.describe 'CRM board performance', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:owner) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:pipeline) { create(:crm_pipeline, account: account) }
  let(:stage) { create(:crm_stage, :entry, account: account, pipeline: pipeline) }
  let(:source) { create(:crm_source, account: account) }
  let(:headers) { admin.create_new_auth_token }

  # A single contact per batch keeps the fixture cheap; the preloads are per record either way, so
  # an N+1 would still show up as one query per card.
  def seed_deals(count, position_offset: 0)
    contact = create(:contact, account: account)

    count.times do |index|
      deal = create(:crm_deal, account: account, pipeline: pipeline, stage: stage, contact: contact,
                               owner: owner, source: source, position: position_offset + ((index + 1) * 1000))
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      create(:crm_deal_conversation, deal: deal, conversation: conversation, is_origin: true)
      create(:crm_activity, account: account, deal: deal, user: owner, due_at: 3.days.from_now)
    end
  end

  def count_queries
    queries = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      queries += 1 unless payload[:cached] || payload[:name].in?(['SCHEMA', 'TRANSACTION'])
    end

    yield
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  describe 'GET /api/v1/accounts/{account.id}/crm/deals' do
    it 'costs the same number of queries with 30 cards in the column and with 200' do
      seed_deals(30)
      # Warm up: the first authenticated request of the process resolves installation config and
      # the token, which would otherwise be counted only in the baseline.
      get "/api/v1/accounts/#{account.id}/crm/deals", params: { pipeline_id: pipeline.id, stage_id: stage.id }, headers: headers, as: :json

      baseline = count_queries do
        get "/api/v1/accounts/#{account.id}/crm/deals", params: { pipeline_id: pipeline.id, stage_id: stage.id }, headers: headers,
                                                        as: :json
      end
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].size).to eq(25)

      seed_deals(170, position_offset: 1_000_000)

      scaled = count_queries do
        get "/api/v1/accounts/#{account.id}/crm/deals", params: { pipeline_id: pipeline.id, stage_id: stage.id }, headers: headers,
                                                        as: :json
      end

      expect(response.parsed_body['meta']['count']).to eq(200)
      expect(scaled).to eq(baseline)
      # A page of 25 cards resolving each relation on its own would be well over a hundred queries.
      expect(baseline).to be < 30
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/crm/deals/{deal.id}/activities' do
    it 'costs the same number of queries with 30 activities and with 200' do
      seed_deals(1)
      deal = Crm::Deal.last
      create_list(:crm_activity, 29, account: account, deal: deal, user: owner)
      get "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}/activities", headers: headers, as: :json

      baseline = count_queries do
        get "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}/activities", headers: headers, as: :json
      end
      expect(response).to have_http_status(:success)

      create_list(:crm_activity, 170, account: account, deal: deal, user: owner)

      scaled = count_queries do
        get "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}/activities", headers: headers, as: :json
      end

      expect(scaled).to eq(baseline)
      expect(baseline).to be < 20
    end
  end
end
