require 'rails_helper'

RSpec.describe 'CRM Deal Activities API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:foreign_admin) { create(:user, account: other_account, role: :administrator) }
  let(:pipeline) { create(:crm_pipeline, account: account) }
  let(:stage) { create(:crm_stage, account: account, pipeline: pipeline) }
  let(:deal) { create(:crm_deal, account: account, pipeline: pipeline, stage: stage) }
  let!(:activity) { create(:crm_activity, account: account, deal: deal, user: admin, content: 'Ligamos para o produtor') }
  let(:base_url) { "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}/activities" }

  describe 'GET /api/v1/accounts/{account.id}/crm/deals/:deal_id/activities' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get base_url

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user belongs to another account' do
      it 'does not expose this account resources' do
        get base_url, headers: foreign_admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'lists the timeline of the deal in chronological order' do
        newer = create(:crm_activity, account: account, deal: deal, user: agent, created_at: 1.minute.from_now)

        get base_url, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        payload = response.parsed_body['payload']
        expect(payload.pluck('id')).to eq([activity.id, newer.id])
        expect(payload.first['content']).to eq('Ligamos para o produtor')
        expect(payload.first['user']['id']).to eq(admin.id)
      end

      it 'is readable by an agent' do
        get base_url, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end

      it 'does not list activities of another deal' do
        other_deal = create(:crm_deal, account: account, pipeline: pipeline, stage: stage)
        other_activity = create(:crm_activity, account: account, deal: other_deal)

        get base_url, headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].pluck('id')).not_to include(other_activity.id)
      end

      it 'returns not found for a deal of another account' do
        foreign_deal = create(:crm_deal, account: other_account)

        get "/api/v1/accounts/#{account.id}/crm/deals/#{foreign_deal.id}/activities",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end

      it 'denies an agent access to the timeline of a restricted deal owned by someone else' do
        restricted_pipeline = create(:crm_pipeline, :restricted_by_owner, account: account)
        restricted_stage = create(:crm_stage, account: account, pipeline: restricted_pipeline)
        restricted_deal = create(:crm_deal, account: account, pipeline: restricted_pipeline, stage: restricted_stage, owner: admin)

        get "/api/v1/accounts/#{account.id}/crm/deals/#{restricted_deal.id}/activities",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/crm/deals/:deal_id/activities/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "#{base_url}/#{activity.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns the activity' do
        get "#{base_url}/#{activity.id}", headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['id']).to eq(activity.id)
        expect(response.parsed_body['content']).to eq('Ligamos para o produtor')
        expect(response.parsed_body['user']['id']).to eq(admin.id)
      end

      it 'returns not found for an activity of another deal' do
        other_deal = create(:crm_deal, account: account, pipeline: pipeline, stage: stage)
        other_activity = create(:crm_activity, account: account, deal: other_deal, user: admin)

        get "#{base_url}/#{other_activity.id}", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/crm/deals/:deal_id/activities' do
    let(:valid_params) { { activity: { kind: 'task', content: 'Enviar proposta', due_at: 1.day.from_now.iso8601 } } }

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        expect { post base_url, params: valid_params, as: :json }.not_to change(Crm::Activity, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'creates the activity attributed to the current user' do
        expect do
          post base_url, params: valid_params, headers: agent.create_new_auth_token, as: :json
        end.to change(Crm::Activity, :count).by(1)

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['kind']).to eq('task')
        expect(response.parsed_body['content']).to eq('Enviar proposta')
        expect(response.parsed_body['deal_id']).to eq(deal.id)
        expect(response.parsed_body['user']['id']).to eq(agent.id)

        created = Crm::Activity.find(response.parsed_body['id'])
        expect(created.account_id).to eq(account.id)
        expect(created.user_id).to eq(agent.id)
      end

      it 'returns unprocessable entity when the activity payload is missing' do
        post base_url, params: {}, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/crm/deals/:deal_id/activities/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        patch "#{base_url}/#{activity.id}", params: { activity: { content: 'Novo' } }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'updates the activity' do
        completed_at = 1.hour.ago

        patch "#{base_url}/#{activity.id}",
              params: { activity: { content: 'Follow up feito', completed_at: completed_at.iso8601 } },
              headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(activity.reload.content).to eq('Follow up feito')
        expect(activity.completed_at).to be_within(1.second).of(completed_at)
      end

      it 'returns not found for an activity of another deal' do
        other_deal = create(:crm_deal, account: account, pipeline: pipeline, stage: stage)
        other_activity = create(:crm_activity, account: account, deal: other_deal)

        patch "#{base_url}/#{other_activity.id}",
              params: { activity: { content: 'Novo' } }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/crm/deals/:deal_id/activities/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        delete "#{base_url}/#{activity.id}"

        expect(response).to have_http_status(:unauthorized)
        expect(Crm::Activity.exists?(activity.id)).to be(true)
      end
    end

    context 'when the user is an agent' do
      it 'is not allowed to delete activities' do
        delete "#{base_url}/#{activity.id}", headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(Crm::Activity.exists?(activity.id)).to be(true)
      end
    end

    context 'when the user is an administrator' do
      it 'deletes the activity' do
        delete "#{base_url}/#{activity.id}", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(Crm::Activity.exists?(activity.id)).to be(false)
      end
    end
  end
end
