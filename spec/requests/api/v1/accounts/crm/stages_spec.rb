require 'rails_helper'

RSpec.describe 'CRM Stages API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:foreign_admin) { create(:user, account: other_account, role: :administrator) }
  let(:pipeline) { create(:crm_pipeline, account: account) }
  let!(:stage) { create(:crm_stage, account: account, pipeline: pipeline, name: 'Qualificacao', position: 1) }

  describe 'GET /api/v1/accounts/{account.id}/crm/pipelines/:pipeline_id/stages' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user belongs to another account' do
      it 'does not expose this account resources' do
        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
            headers: foreign_admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'lists the stages of the pipeline ordered by position' do
        entry = create(:crm_stage, :entry, account: account, pipeline: pipeline, position: 0)

        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload'].pluck('id')).to eq([entry.id, stage.id])
      end

      it 'is readable by an agent' do
        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end

      it 'returns the totals of the whole stage, ignoring archived and closed deals' do
        create(:crm_deal, account: account, pipeline: pipeline, stage: stage, value_cents: 30_000)
        create(:crm_deal, account: account, pipeline: pipeline, stage: stage, value_cents: 70_000)
        create(:crm_deal, :archived, account: account, pipeline: pipeline, stage: stage, value_cents: 500_000)
        create(:crm_deal, :won, account: account, pipeline: pipeline, stage: stage, value_cents: 900_000)

        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
            headers: admin.create_new_auth_token, as: :json

        payload = response.parsed_body['payload'].find { |stage_payload| stage_payload['id'] == stage.id }
        expect(payload['deals_count']).to eq(2)
        expect(payload['deals_value_cents']).to eq(100_000)
      end

      # The header of a column publishes two numbers: the total of the stage, which is what the WIP
      # limit is about, and the total restricted to the board filters, which is what the cards
      # below it add up to.
      describe 'filtered aggregates' do
        before do
          create(:crm_deal, account: account, pipeline: pipeline, stage: stage, title: 'Fazenda Boa Vista', value_cents: 30_000)
          create(:crm_deal, account: account, pipeline: pipeline, stage: stage, title: 'Sitio Sao Jorge', value_cents: 70_000)
        end

        it 'mirrors the stage total when no filter is applied' do
          get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
              headers: admin.create_new_auth_token, as: :json

          payload = response.parsed_body['payload'].find { |stage_payload| stage_payload['id'] == stage.id }
          expect(payload).to include('deals_count' => 2, 'deals_value_cents' => 100_000,
                                     'filtered_deals_count' => 2, 'filtered_deals_value_cents' => 100_000)
        end

        it 'restricts the filtered aggregate to the search term while keeping the stage total intact' do
          get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
              params: { q: 'Boa Vista' }, headers: admin.create_new_auth_token, as: :json

          payload = response.parsed_body['payload'].find { |stage_payload| stage_payload['id'] == stage.id }
          expect(payload).to include('deals_count' => 2, 'deals_value_cents' => 100_000,
                                     'filtered_deals_count' => 1, 'filtered_deals_value_cents' => 30_000)
        end

        it 'accepts the same owner and source filters as the deals index' do
          owned = create(:crm_deal, account: account, pipeline: pipeline, stage: stage, owner: agent, value_cents: 11_000)

          get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
              params: { owner_id: agent.id }, headers: admin.create_new_auth_token, as: :json

          payload = response.parsed_body['payload'].find { |stage_payload| stage_payload['id'] == stage.id }
          expect(payload['deals_count']).to eq(3)
          expect(payload['filtered_deals_count']).to eq(1)
          expect(payload['filtered_deals_value_cents']).to eq(owned.value_cents)
        end

        it 'follows the status filter instead of the still in play default' do
          create(:crm_deal, :won, account: account, pipeline: pipeline, stage: stage, value_cents: 90_000)

          get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
              params: { status: 'won' }, headers: admin.create_new_auth_token, as: :json

          payload = response.parsed_body['payload'].find { |stage_payload| stage_payload['id'] == stage.id }
          expect(payload['deals_count']).to eq(2)
          expect(payload['filtered_deals_count']).to eq(1)
          expect(payload['filtered_deals_value_cents']).to eq(90_000)
        end

        it 'never counts an archived card on either number' do
          create(:crm_deal, :archived, account: account, pipeline: pipeline, stage: stage,
                                       title: 'Fazenda Boa Vista II', value_cents: 500_000)

          get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
              params: { q: 'Boa Vista' }, headers: admin.create_new_auth_token, as: :json

          payload = response.parsed_body['payload'].find { |stage_payload| stage_payload['id'] == stage.id }
          expect(payload['deals_count']).to eq(2)
          expect(payload['filtered_deals_count']).to eq(1)
        end
      end

      it 'returns zeroed totals for a stage without deals' do
        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
            headers: admin.create_new_auth_token, as: :json

        payload = response.parsed_body['payload'].find { |stage_payload| stage_payload['id'] == stage.id }
        expect(payload['deals_count']).to eq(0)
        expect(payload['deals_value_cents']).to eq(0)
      end

      it 'does not count deals of another stage of the same pipeline' do
        other_stage = create(:crm_stage, account: account, pipeline: pipeline, position: 2)
        create(:crm_deal, account: account, pipeline: pipeline, stage: other_stage, value_cents: 45_000)
        create(:crm_deal, account: account, pipeline: pipeline, stage: stage, value_cents: 15_000)

        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
            headers: admin.create_new_auth_token, as: :json

        totals = response.parsed_body['payload'].to_h { |stage_payload| [stage_payload['id'], stage_payload['deals_value_cents']] }
        expect(totals[stage.id]).to eq(15_000)
        expect(totals[other_stage.id]).to eq(45_000)
      end

      it 'hides from an agent the totals of deals owned by someone else in a restricted pipeline' do
        restricted_pipeline = create(:crm_pipeline, :restricted_by_owner, account: account)
        restricted_stage = create(:crm_stage, account: account, pipeline: restricted_pipeline)
        create(:crm_deal, account: account, pipeline: restricted_pipeline, stage: restricted_stage, owner: agent, value_cents: 20_000)
        create(:crm_deal, account: account, pipeline: restricted_pipeline, stage: restricted_stage, owner: admin, value_cents: 80_000)

        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{restricted_pipeline.id}/stages",
            headers: agent.create_new_auth_token, as: :json

        payload = response.parsed_body['payload'].find { |stage_payload| stage_payload['id'] == restricted_stage.id }
        expect(payload['deals_count']).to eq(1)
        expect(payload['deals_value_cents']).to eq(20_000)
      end

      it 'returns not found for a pipeline of another account' do
        foreign_pipeline = create(:crm_pipeline, account: other_account)

        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{foreign_pipeline.id}/stages",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/crm/pipelines/:pipeline_id/stages/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns the stage' do
        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['id']).to eq(stage.id)
        expect(response.parsed_body['name']).to eq('Qualificacao')
      end

      it 'returns the totals of the stage' do
        create(:crm_deal, account: account, pipeline: pipeline, stage: stage, value_cents: 25_000)

        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}",
            headers: agent.create_new_auth_token, as: :json

        expect(response.parsed_body['deals_count']).to eq(1)
        expect(response.parsed_body['deals_value_cents']).to eq(25_000)
      end

      it 'returns not found for a stage of another pipeline' do
        other_pipeline = create(:crm_pipeline, account: account)
        other_stage = create(:crm_stage, account: account, pipeline: other_pipeline)

        get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{other_stage.id}",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/crm/pipelines/:pipeline_id/stages' do
    let(:valid_params) do
      { stage: { name: 'Proposta', category: 'open', position: 3, color: 'violet', probability: 60, wip_limit: 5, rotting_days: 7 } }
    end

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages", params: valid_params, as: :json
        end.not_to change(Crm::Stage, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is an agent' do
      it 'is not allowed to create stages' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
               params: valid_params, headers: agent.create_new_auth_token, as: :json
        end.not_to change(Crm::Stage, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is an administrator' do
      it 'creates the stage inside the pipeline and the current account' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
               params: valid_params, headers: admin.create_new_auth_token, as: :json
        end.to change(Crm::Stage, :count).by(1)

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['name']).to eq('Proposta')
        expect(response.parsed_body['pipeline_id']).to eq(pipeline.id)
        expect(response.parsed_body['wip_limit']).to eq(5)
        expect(response.parsed_body['color']).to eq('violet')

        created = Crm::Stage.find(response.parsed_body['id'])
        expect(created.account_id).to eq(account.id)
      end

      it 'returns unprocessable entity for a color outside the token list' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
               params: { stage: { name: 'Invalida', color: '#ff0000' } },
               headers: admin.create_new_auth_token, as: :json
        end.not_to change(Crm::Stage, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'accepts a stage without a color' do
        post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
             params: { stage: { name: 'Sem cor' } }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['color']).to be_nil
      end

      it 'returns unprocessable entity for an invalid probability' do
        post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
             params: { stage: { name: 'Invalida', probability: 200 } },
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/crm/pipelines/:pipeline_id/stages/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}",
              params: { stage: { name: 'Novo' } }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is an agent' do
      it 'is not allowed to update stages' do
        patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}",
              params: { stage: { name: 'Novo' } }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(stage.reload.name).to eq('Qualificacao')
      end
    end

    context 'when the user is an administrator' do
      it 'updates the stage' do
        patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}",
              params: { stage: { name: 'Qualificado', wip_limit: 3 } },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(stage.reload.name).to eq('Qualificado')
        expect(stage.wip_limit).to eq(3)
      end

      it 'returns not found for a stage of another pipeline' do
        other_pipeline = create(:crm_pipeline, account: account)
        other_stage = create(:crm_stage, account: account, pipeline: other_pipeline)

        patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{other_stage.id}",
              params: { stage: { name: 'Novo' } }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/crm/pipelines/:pipeline_id/stages/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}"

        expect(response).to have_http_status(:unauthorized)
        expect(Crm::Stage.exists?(stage.id)).to be(true)
      end
    end

    context 'when the user is an agent' do
      it 'is not allowed to delete stages' do
        delete "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}",
               headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(Crm::Stage.exists?(stage.id)).to be(true)
      end
    end

    context 'when the user is an administrator' do
      it 'deletes a stage without deals' do
        delete "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}",
               headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(Crm::Stage.exists?(stage.id)).to be(false)
      end

      it 'returns unprocessable entity when the stage still holds deals' do
        create(:crm_deal, account: account, pipeline: pipeline, stage: stage)

        delete "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}",
               headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to be_present
        expect(Crm::Stage.exists?(stage.id)).to be(true)
      end
    end
  end
end
