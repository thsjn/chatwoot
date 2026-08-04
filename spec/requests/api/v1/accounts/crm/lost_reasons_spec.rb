require 'rails_helper'

RSpec.describe 'CRM Lost Reasons API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:foreign_admin) { create(:user, account: other_account, role: :administrator) }
  let!(:lost_reason) { create(:crm_lost_reason, account: account, name: 'Preco', position: 1) }

  describe 'GET /api/v1/accounts/{account.id}/crm/lost_reasons' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/crm/lost_reasons"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user belongs to another account' do
      it 'does not expose this account resources' do
        get "/api/v1/accounts/#{account.id}/crm/lost_reasons",
            headers: foreign_admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      let!(:foreign_lost_reason) { create(:crm_lost_reason, account: other_account) }

      it 'lists only the lost reasons of the current account ordered by position' do
        first = create(:crm_lost_reason, account: account, position: 0)

        get "/api/v1/accounts/#{account.id}/crm/lost_reasons",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        ids = response.parsed_body['payload'].pluck('id')
        expect(ids).to eq([first.id, lost_reason.id])
        expect(ids).not_to include(foreign_lost_reason.id)
      end

      it 'is readable by an agent, who needs the list to close a deal' do
        get "/api/v1/accounts/#{account.id}/crm/lost_reasons",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end

      # An inactive reason is rejected by `Crm::MoveDealService`, so offering it in the picker
      # only builds a dead end for whoever chooses it.
      it 'hides the inactive reasons by default' do
        inactive = create(:crm_lost_reason, :inactive, account: account)

        get "/api/v1/accounts/#{account.id}/crm/lost_reasons",
            headers: agent.create_new_auth_token, as: :json

        ids = response.parsed_body['payload'].pluck('id')
        expect(ids).to include(lost_reason.id)
        expect(ids).not_to include(inactive.id)
      end

      it 'lists the inactive reasons when the administration asks for them' do
        inactive = create(:crm_lost_reason, :inactive, account: account)

        get "/api/v1/accounts/#{account.id}/crm/lost_reasons",
            params: { include_inactive: true }, headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['payload'].pluck('id')).to include(inactive.id)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/crm/lost_reasons/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/crm/lost_reasons/#{lost_reason.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns the lost reason' do
        get "/api/v1/accounts/#{account.id}/crm/lost_reasons/#{lost_reason.id}",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['id']).to eq(lost_reason.id)
        expect(response.parsed_body['name']).to eq('Preco')
      end

      it 'returns not found for a lost reason of another account' do
        foreign_lost_reason = create(:crm_lost_reason, account: other_account)

        get "/api/v1/accounts/#{account.id}/crm/lost_reasons/#{foreign_lost_reason.id}",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/crm/lost_reasons' do
    let(:valid_params) { { lost_reason: { name: 'Sem budget', position: 4, active: true } } }

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm/lost_reasons", params: valid_params, as: :json
        end.not_to change(Crm::LostReason, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is an agent' do
      it 'is not allowed to create lost reasons' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm/lost_reasons",
               params: valid_params, headers: agent.create_new_auth_token, as: :json
        end.not_to change(Crm::LostReason, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is an administrator' do
      it 'creates the lost reason' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm/lost_reasons",
               params: valid_params, headers: admin.create_new_auth_token, as: :json
        end.to change(Crm::LostReason, :count).by(1)

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['name']).to eq('Sem budget')
        expect(Crm::LostReason.find(response.parsed_body['id']).account_id).to eq(account.id)
      end

      it 'returns unprocessable entity for a duplicated name' do
        post "/api/v1/accounts/#{account.id}/crm/lost_reasons",
             params: { lost_reason: { name: lost_reason.name } }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/crm/lost_reasons/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/crm/lost_reasons/#{lost_reason.id}",
              params: { lost_reason: { name: 'Novo' } }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is an agent' do
      it 'is not allowed to update lost reasons' do
        patch "/api/v1/accounts/#{account.id}/crm/lost_reasons/#{lost_reason.id}",
              params: { lost_reason: { name: 'Novo' } }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(lost_reason.reload.name).to eq('Preco')
      end
    end

    context 'when the user is an administrator' do
      it 'updates the lost reason' do
        patch "/api/v1/accounts/#{account.id}/crm/lost_reasons/#{lost_reason.id}",
              params: { lost_reason: { name: 'Preco alto', active: false } },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['active']).to be(false)
        expect(lost_reason.reload.name).to eq('Preco alto')
      end

      it 'returns not found for a lost reason of another account' do
        foreign_lost_reason = create(:crm_lost_reason, account: other_account)

        patch "/api/v1/accounts/#{account.id}/crm/lost_reasons/#{foreign_lost_reason.id}",
              params: { lost_reason: { name: 'Novo' } }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/crm/lost_reasons/:id' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/crm/lost_reasons/#{lost_reason.id}"

        expect(response).to have_http_status(:unauthorized)
        expect(Crm::LostReason.exists?(lost_reason.id)).to be(true)
      end
    end

    context 'when the user is an agent' do
      it 'is not allowed to delete lost reasons' do
        delete "/api/v1/accounts/#{account.id}/crm/lost_reasons/#{lost_reason.id}",
               headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(Crm::LostReason.exists?(lost_reason.id)).to be(true)
      end
    end

    context 'when the user is an administrator' do
      it 'deletes the lost reason and nullifies it on the deals' do
        deal = create(:crm_deal, account: account, lost_reason: lost_reason)

        delete "/api/v1/accounts/#{account.id}/crm/lost_reasons/#{lost_reason.id}",
               headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(Crm::LostReason.exists?(lost_reason.id)).to be(false)
        expect(deal.reload.lost_reason_id).to be_nil
      end
    end
  end
end
