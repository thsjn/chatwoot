require 'rails_helper'

RSpec.describe 'CRM Deals API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:foreign_admin) { create(:user, account: other_account, role: :administrator) }
  let(:pipeline) { create(:crm_pipeline, account: account) }
  let(:entry_stage) { create(:crm_stage, :entry, account: account, pipeline: pipeline, position: 0) }
  let(:stage) { create(:crm_stage, account: account, pipeline: pipeline, position: 1) }
  let(:contact) { create(:contact, account: account) }
  let!(:deal) do
    create(:crm_deal, account: account, pipeline: pipeline, stage: stage, contact: contact, title: 'Fazenda Boa Vista', position: 1000)
  end

  describe 'GET /api/v1/accounts/{account.id}/crm/deals' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/crm/deals"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user belongs to another account' do
      it 'does not expose this account resources' do
        get "/api/v1/accounts/#{account.id}/crm/deals",
            headers: foreign_admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as an administrator' do
      it 'lists the deals of the account with meta and lock_version' do
        get "/api/v1/accounts/#{account.id}/crm/deals",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['meta']['count']).to eq(1)
        expect(response.parsed_body['meta']['current_page']).to eq(1)

        payload = response.parsed_body['payload']
        expect(payload.pluck('id')).to eq([deal.id])
        expect(payload.first).to have_key('lock_version')
        expect(payload.first['lock_version']).to eq(deal.lock_version)
        expect(payload.first['contact']['id']).to eq(contact.id)
      end

      it 'exposes the next open activity due in the future' do
        create(:crm_activity, :task, account: account, deal: deal, due_at: 3.days.from_now)
        next_task = create(:crm_activity, :task, account: account, deal: deal, due_at: 1.day.from_now)

        get "/api/v1/accounts/#{account.id}/crm/deals",
            headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].first['next_activity_at']).to eq(next_task.due_at.to_i)
      end

      it 'ignores overdue and completed activities when resolving the next activity' do
        create(:crm_activity, :task, account: account, deal: deal, due_at: 1.day.ago)
        create(:crm_activity, :task, :completed, account: account, deal: deal, due_at: 1.day.from_now)

        get "/api/v1/accounts/#{account.id}/crm/deals",
            headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].first['next_activity_at']).to be_nil
      end

      it 'returns a null next activity when the deal has no activity at all' do
        get "/api/v1/accounts/#{account.id}/crm/deals",
            headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].first).to have_key('next_activity_at')
        expect(response.parsed_body['payload'].first['next_activity_at']).to be_nil
      end

      it 'exposes the conversations linked to the deal and flags the origin one' do
        origin_conversation = create(:conversation, account: account, contact: contact)
        other_conversation = create(:conversation, account: account, contact: contact)
        create(:crm_deal_conversation, :origin, deal: deal, conversation: origin_conversation)
        create(:crm_deal_conversation, deal: deal, conversation: other_conversation)

        get "/api/v1/accounts/#{account.id}/crm/deals",
            headers: admin.create_new_auth_token, as: :json

        conversations = response.parsed_body['payload'].first['conversations']
        expect(conversations.pluck('id')).to contain_exactly(origin_conversation.id, other_conversation.id)

        origin_payload = conversations.find { |conversation| conversation['id'] == origin_conversation.id }
        expect(origin_payload['is_origin']).to be(true)
        expect(origin_payload['display_id']).to eq(origin_conversation.display_id)
        expect(origin_payload['status']).to eq(origin_conversation.status)
        expect(origin_payload['inbox']).to eq(
          'id' => origin_conversation.inbox.id,
          'name' => origin_conversation.inbox.name,
          'channel_type' => origin_conversation.inbox.channel_type
        )
        expect(conversations.find { |conversation| conversation['id'] == other_conversation.id }['is_origin']).to be(false)
      end

      it 'returns an empty conversation list for a deal without conversations' do
        get "/api/v1/accounts/#{account.id}/crm/deals",
            headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].first['conversations']).to eq([])
      end

      it 'does not list deals of other accounts' do
        foreign_deal = create(:crm_deal, account: other_account)

        get "/api/v1/accounts/#{account.id}/crm/deals",
            headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].pluck('id')).not_to include(foreign_deal.id)
      end

      it 'does not list archived deals' do
        archived = create(:crm_deal, :archived, account: account, pipeline: pipeline, stage: stage)

        get "/api/v1/accounts/#{account.id}/crm/deals",
            headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].pluck('id')).not_to include(archived.id)
      end
    end

    context 'when filtering' do
      let(:other_pipeline) { create(:crm_pipeline, account: account) }
      let(:other_stage) { create(:crm_stage, account: account, pipeline: other_pipeline) }
      let!(:other_deal) do
        create(:crm_deal, account: account, pipeline: other_pipeline, stage: other_stage, owner: agent, title: 'Sitio Sao Jorge', status: :won)
      end

      it 'filters by pipeline_id' do
        get "/api/v1/accounts/#{account.id}/crm/deals",
            params: { pipeline_id: pipeline.id }, headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].pluck('id')).to eq([deal.id])
      end

      it 'filters by stage_id' do
        get "/api/v1/accounts/#{account.id}/crm/deals",
            params: { stage_id: other_stage.id }, headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].pluck('id')).to eq([other_deal.id])
      end

      it 'filters by owner_id' do
        get "/api/v1/accounts/#{account.id}/crm/deals",
            params: { owner_id: agent.id }, headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].pluck('id')).to eq([other_deal.id])
      end

      it 'filters by status' do
        get "/api/v1/accounts/#{account.id}/crm/deals",
            params: { status: 'won' }, headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].pluck('id')).to eq([other_deal.id])
      end

      it 'filters by the q search term on the title' do
        get "/api/v1/accounts/#{account.id}/crm/deals",
            params: { q: 'boa vista' }, headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].pluck('id')).to eq([deal.id])
      end

      it 'ignores an unknown status value' do
        get "/api/v1/accounts/#{account.id}/crm/deals",
            params: { status: 'whatever' }, headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(deal.id, other_deal.id)
      end
    end

    context 'when the pipeline is restricted by owner' do
      let(:restricted_pipeline) { create(:crm_pipeline, :restricted_by_owner, account: account) }
      let(:restricted_stage) { create(:crm_stage, account: account, pipeline: restricted_pipeline) }
      let!(:own_deal) do
        create(:crm_deal, account: account, pipeline: restricted_pipeline, stage: restricted_stage, owner: agent)
      end
      let!(:ownerless_deal) do
        create(:crm_deal, account: account, pipeline: restricted_pipeline, stage: restricted_stage, owner: nil)
      end
      let!(:foreign_owner_deal) do
        create(:crm_deal, account: account, pipeline: restricted_pipeline, stage: restricted_stage, owner: admin)
      end

      it 'hides the deals owned by someone else from an agent' do
        get "/api/v1/accounts/#{account.id}/crm/deals",
            params: { pipeline_id: restricted_pipeline.id }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        ids = response.parsed_body['payload'].pluck('id')
        expect(ids).to contain_exactly(own_deal.id, ownerless_deal.id)
        expect(ids).not_to include(foreign_owner_deal.id)
      end

      it 'shows every deal to an administrator' do
        get "/api/v1/accounts/#{account.id}/crm/deals",
            params: { pipeline_id: restricted_pipeline.id }, headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(own_deal.id, ownerless_deal.id, foreign_owner_deal.id)
      end

      it 'still shows the deals of an unrestricted pipeline to an agent' do
        get "/api/v1/accounts/#{account.id}/crm/deals",
            params: { pipeline_id: pipeline.id }, headers: agent.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].pluck('id')).to eq([deal.id])
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/crm/deals/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns the deal' do
        get "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['id']).to eq(deal.id)
        expect(response.parsed_body['title']).to eq('Fazenda Boa Vista')
        expect(response.parsed_body['lock_version']).to eq(deal.lock_version)
      end

      it 'returns the next activity and the linked conversations of a single deal' do
        next_task = create(:crm_activity, :task, account: account, deal: deal, due_at: 2.days.from_now)
        create(:crm_activity, :task, :completed, account: account, deal: deal, due_at: 1.hour.from_now)
        conversation = create(:conversation, account: account, contact: contact)
        create(:crm_deal_conversation, :origin, deal: deal, conversation: conversation)

        get "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}",
            headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['next_activity_at']).to eq(next_task.due_at.to_i)
        expect(response.parsed_body['conversations'].first['id']).to eq(conversation.id)
        expect(response.parsed_body['conversations'].first['is_origin']).to be(true)
      end

      it 'returns not found for a deal of another account' do
        foreign_deal = create(:crm_deal, account: other_account)

        get "/api/v1/accounts/#{account.id}/crm/deals/#{foreign_deal.id}",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end

      it 'denies an agent access to a restricted deal owned by someone else' do
        restricted_pipeline = create(:crm_pipeline, :restricted_by_owner, account: account)
        restricted_stage = create(:crm_stage, account: account, pipeline: restricted_pipeline)
        foreign_owner_deal = create(:crm_deal, account: account, pipeline: restricted_pipeline, stage: restricted_stage, owner: admin)

        get "/api/v1/accounts/#{account.id}/crm/deals/#{foreign_owner_deal.id}",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/crm/deals' do
    let(:valid_params) do
      {
        deal: {
          title: 'Fazenda Santa Clara', contact_id: contact.id, pipeline_id: pipeline.id, stage_id: stage.id,
          value_cents: 250_000, currency: 'BRL', owner_id: agent.id, custom_attributes: { hectares: 320 },
          utm: { source: 'meta' }
        }
      }
    end

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm/deals", params: valid_params, as: :json
        end.not_to change(Crm::Deal, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'creates the deal on the given stage' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm/deals",
               params: valid_params, headers: admin.create_new_auth_token, as: :json
        end.to change(Crm::Deal, :count).by(1)

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['title']).to eq('Fazenda Santa Clara')
        expect(response.parsed_body['stage_id']).to eq(stage.id)
        expect(response.parsed_body['value']).to eq(2500.0)
        expect(response.parsed_body['custom_attributes']['hectares']).to eq(320)

        created = Crm::Deal.find(response.parsed_body['id'])
        expect(created.account_id).to eq(account.id)
        expect(created.stage_entered_at).to be_present
      end

      it 'falls back to the entry stage of the pipeline when no stage is given' do
        entry_stage

        post "/api/v1/accounts/#{account.id}/crm/deals",
             params: { deal: { title: 'Sem estagio', contact_id: contact.id, pipeline_id: pipeline.id } },
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['stage_id']).to eq(entry_stage.id)
      end

      it 'is allowed for an agent' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm/deals",
               params: valid_params, headers: agent.create_new_auth_token, as: :json
        end.to change(Crm::Deal, :count).by(1)

        expect(response).to have_http_status(:success)
      end

      it 'rejects a contact from another account' do
        foreign_contact = create(:contact, account: other_account)

        post "/api/v1/accounts/#{account.id}/crm/deals",
             params: { deal: { title: 'Invalido', contact_id: foreign_contact.id, pipeline_id: pipeline.id, stage_id: stage.id } },
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/crm/deals/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}",
              params: { deal: { title: 'Novo' } }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'updates the editable attributes' do
        patch "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}",
              params: { deal: { title: 'Fazenda Boa Vista II', value_cents: 999_00, owner_id: agent.id } },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(deal.reload.title).to eq('Fazenda Boa Vista II')
        expect(deal.value_cents).to eq(999_00)
        expect(deal.owner_id).to eq(agent.id)
      end

      it 'ignores stage_id and status when they are sent' do
        another_stage = create(:crm_stage, account: account, pipeline: pipeline, position: 5)

        patch "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}",
              params: { deal: { title: 'Tentativa', stage_id: another_stage.id, status: 'won' } },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(deal.reload.title).to eq('Tentativa')
        expect(deal.stage_id).to eq(stage.id)
        expect(deal.status).to eq('open')
      end

      it 'ignores pipeline_id when it is sent' do
        another_pipeline = create(:crm_pipeline, account: account)

        patch "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}",
              params: { deal: { pipeline_id: another_pipeline.id } },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(deal.reload.pipeline_id).to eq(pipeline.id)
      end

      # Pre-filling the reason here would let the client satisfy `lost_reason_required` before
      # the move and slip a card into a lost stage without ever choosing a reason.
      it 'ignores lost_reason_id when it is sent' do
        lost_reason = create(:crm_lost_reason, account: account)

        patch "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}",
              params: { deal: { lost_reason_id: lost_reason.id } },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(deal.reload.lost_reason_id).to be_nil
      end

      it 'returns not found for a deal of another account' do
        foreign_deal = create(:crm_deal, account: other_account)

        patch "/api/v1/accounts/#{account.id}/crm/deals/#{foreign_deal.id}",
              params: { deal: { title: 'Novo' } }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/crm/deals/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}"

        expect(response).to have_http_status(:unauthorized)
        expect(deal.reload.archived_at).to be_nil
      end
    end

    context 'when the user is an agent' do
      it 'is not allowed to archive deals' do
        delete "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}",
               headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(deal.reload.archived_at).to be_nil
      end
    end

    context 'when the user is an administrator' do
      it 'archives the deal instead of deleting it' do
        expect do
          delete "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}",
                 headers: admin.create_new_auth_token, as: :json
        end.not_to change(Crm::Deal, :count)

        expect(response).to have_http_status(:ok)
        expect(Crm::Deal.exists?(deal.id)).to be(true)
        expect(deal.reload.archived_at).to be_present
      end

      it 'removes the archived deal from the index' do
        delete "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}",
               headers: admin.create_new_auth_token, as: :json

        get "/api/v1/accounts/#{account.id}/crm/deals",
            headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].pluck('id')).not_to include(deal.id)
        expect(response.parsed_body['meta']['count']).to eq(0)
      end
    end
  end
end
