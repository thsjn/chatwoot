require 'rails_helper'

RSpec.describe 'CRM Deal move API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:foreign_admin) { create(:user, account: other_account, role: :administrator) }

  let(:pipeline) { create(:crm_pipeline, account: account) }
  let(:origin_stage) { create(:crm_stage, account: account, pipeline: pipeline, position: 0) }
  let(:destination_stage) { create(:crm_stage, account: account, pipeline: pipeline, position: 1) }
  let(:won_stage) { create(:crm_stage, :won, account: account, pipeline: pipeline, position: 2) }
  let(:lost_stage) { create(:crm_stage, :lost, account: account, pipeline: pipeline, position: 3) }
  let(:lost_reason) { create(:crm_lost_reason, account: account) }

  let(:deal) do
    create(:crm_deal, account: account, pipeline: pipeline, stage: origin_stage, position: 1000, stage_entered_at: 2.hours.ago)
  end
  let(:move_url) { "/api/v1/accounts/#{account.id}/crm/deals/#{deal.id}/move" }

  describe 'authentication and isolation' do
    it 'returns unauthorized when unauthenticated' do
      patch move_url, params: { stage_id: destination_stage.id }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(deal.reload.stage_id).to eq(origin_stage.id)
    end

    it 'does not expose the deal to a user of another account' do
      patch move_url, params: { stage_id: destination_stage.id },
                      headers: foreign_admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(deal.reload.stage_id).to eq(origin_stage.id)
    end

    it 'returns not found for a deal of another account' do
      foreign_deal = create(:crm_deal, account: other_account)

      patch "/api/v1/accounts/#{account.id}/crm/deals/#{foreign_deal.id}/move",
            params: { stage_id: destination_stage.id }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'contract case 1: a successful move' do
    it 'returns the deal and records the stage transition' do
      patch move_url,
            params: { stage_id: destination_stage.id, position: 1500, lock_version: deal.lock_version },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq(deal.id)
      expect(response.parsed_body['stage_id']).to eq(destination_stage.id)

      expect(deal.reload.stage_id).to eq(destination_stage.id)
      expect(deal.position).to eq(1500)
    end

    it 'creates the transition with the duration spent on the previous stage' do
      # Force the deal (and its own creation transition) to exist before the measured block,
      # so the `by(1)` below reflects only the transition written by the move itself.
      deal

      expect do
        patch move_url, params: { stage_id: destination_stage.id, lock_version: deal.lock_version },
                        headers: admin.create_new_auth_token, as: :json
      end.to change(Crm::StageTransition, :count).by(1)

      # Creating the deal already wrote a transition into `origin_stage`, so the move is the
      # latest entry of the trail and not the only one.
      transition = Crm::StageTransition.where(deal_id: deal.id).chronological.last
      expect(transition.from_stage_id).to eq(origin_stage.id)
      expect(transition.to_stage_id).to eq(destination_stage.id)
      expect(transition.user_id).to eq(admin.id)
      expect(transition.duration_seconds).to be_within(120).of(2.hours.to_i)
      expect(transition.automated).to be(false)
    end

    it 'restarts stage_entered_at' do
      previous_stage_entered_at = deal.stage_entered_at

      patch move_url, params: { stage_id: destination_stage.id, lock_version: deal.lock_version },
                      headers: admin.create_new_auth_token, as: :json

      expect(deal.reload.stage_entered_at).to be > previous_stage_entered_at
      expect(deal.stage_entered_at).to be_within(1.minute).of(Time.current)
    end
  end

  describe 'contract case 2: a stale lock_version' do
    it 'returns conflict with the current deal in the body' do
      deal.update!(title: 'Atualizado por outro agente')
      stale_lock_version = deal.lock_version - 1

      patch move_url, params: { stage_id: destination_stage.id, lock_version: stale_lock_version },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['id']).to eq(deal.id)
      expect(response.parsed_body['stage_id']).to eq(origin_stage.id)
      expect(response.parsed_body['lock_version']).to eq(deal.lock_version)
    end

    it 'does not move the deal nor record a transition' do
      deal.update!(title: 'Atualizado por outro agente')

      expect do
        patch move_url, params: { stage_id: destination_stage.id, lock_version: deal.lock_version - 1 },
                        headers: admin.create_new_auth_token, as: :json
      end.not_to change(Crm::StageTransition, :count)

      expect(deal.reload.stage_id).to eq(origin_stage.id)
    end

    it 'moves the deal when the lock_version is current' do
      deal.update!(title: 'Atualizado por outro agente')

      patch move_url, params: { stage_id: destination_stage.id, lock_version: deal.lock_version },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(deal.reload.stage_id).to eq(destination_stage.id)
    end
  end

  describe 'contract case 3: a lost stage without a lost reason' do
    it 'returns unprocessable entity with the lost_reason_required error code' do
      patch move_url, params: { stage_id: lost_stage.id, lock_version: deal.lock_version },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error_code']).to eq('lost_reason_required')
      expect(deal.reload.stage_id).to eq(origin_stage.id)
      expect(Crm::StageTransition.where(deal_id: deal.id).where.not(from_stage_id: nil)).to be_empty
    end

    it 'moves the deal when the lost reason is given' do
      patch move_url, params: { stage_id: lost_stage.id, lost_reason_id: lost_reason.id, lock_version: deal.lock_version },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(deal.reload.stage_id).to eq(lost_stage.id)
      expect(deal.status).to eq('lost')
      expect(deal.lost_reason_id).to eq(lost_reason.id)
      expect(deal.closed_at).to be_present
    end
  end

  describe 'contract case 3b: a lost stage with a deactivated lost reason' do
    let(:inactive_reason) { create(:crm_lost_reason, :inactive, account: account) }

    it 'returns unprocessable entity with the lost_reason_inactive error code' do
      patch move_url, params: { stage_id: lost_stage.id, lost_reason_id: inactive_reason.id, lock_version: deal.lock_version },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error_code']).to eq('lost_reason_inactive')
      expect(deal.reload.stage_id).to eq(origin_stage.id)
      expect(deal.lost_reason_id).to be_nil
    end

    it 'returns lost_reason_invalid for a reason of another account' do
      foreign_reason = create(:crm_lost_reason, account: other_account)

      patch move_url, params: { stage_id: lost_stage.id, lost_reason_id: foreign_reason.id, lock_version: deal.lock_version },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error_code']).to eq('lost_reason_invalid')
      expect(deal.reload.stage_id).to eq(origin_stage.id)
    end
  end

  describe 'contract case 4: the WIP limit of the destination stage' do
    let(:limited_stage) { create(:crm_stage, account: account, pipeline: pipeline, position: 4, wip_limit: 1) }

    it 'returns unprocessable entity with the wip_limit_exceeded error code' do
      create(:crm_deal, account: account, pipeline: pipeline, stage: limited_stage, status: :open)

      patch move_url, params: { stage_id: limited_stage.id, lock_version: deal.lock_version },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error_code']).to eq('wip_limit_exceeded')
      expect(deal.reload.stage_id).to eq(origin_stage.id)
      expect(Crm::StageTransition.where(deal_id: deal.id).where.not(from_stage_id: nil)).to be_empty
    end

    it 'allows the move while the limit is not reached' do
      patch move_url, params: { stage_id: limited_stage.id, lock_version: deal.lock_version },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(deal.reload.stage_id).to eq(limited_stage.id)
    end
  end

  describe 'contract case 5: an agent without permission over the deal' do
    let(:restricted_pipeline) { create(:crm_pipeline, :restricted_by_owner, account: account) }
    let(:restricted_origin) { create(:crm_stage, account: account, pipeline: restricted_pipeline, position: 0) }
    let(:restricted_destination) { create(:crm_stage, account: account, pipeline: restricted_pipeline, position: 1) }
    let(:foreign_owner_deal) do
      create(:crm_deal, account: account, pipeline: restricted_pipeline, stage: restricted_origin, owner: admin)
    end

    # Chatwoot maps `Pundit::NotAuthorizedError` to 401 in `RequestExceptionHandler`, so every
    # endpoint of the API answers a permission failure with `unauthorized`, not `forbidden`.
    # This endpoint follows the repo convention instead of introducing a custom rescue.
    it 'returns unauthorized' do
      patch "/api/v1/accounts/#{account.id}/crm/deals/#{foreign_owner_deal.id}/move",
            params: { stage_id: restricted_destination.id, lock_version: foreign_owner_deal.lock_version },
            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(foreign_owner_deal.reload.stage_id).to eq(restricted_origin.id)
    end

    it 'allows the agent to move their own deal' do
      own_deal = create(:crm_deal, account: account, pipeline: restricted_pipeline, stage: restricted_origin, owner: agent)

      patch "/api/v1/accounts/#{account.id}/crm/deals/#{own_deal.id}/move",
            params: { stage_id: restricted_destination.id, lock_version: own_deal.lock_version },
            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(own_deal.reload.stage_id).to eq(restricted_destination.id)
    end
  end

  describe 'contract case 6: a missing lock_version' do
    it 'returns unprocessable entity with the lock_version_required error code' do
      patch move_url, params: { stage_id: destination_stage.id, position: 1500 },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error_code']).to eq('lock_version_required')
      expect(deal.reload.stage_id).to eq(origin_stage.id)
      expect(Crm::StageTransition.where(deal_id: deal.id).where.not(from_stage_id: nil)).to be_empty
    end

    it 'is also required to reorder inside the same stage' do
      patch move_url, params: { stage_id: origin_stage.id, position: 2000 },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error_code']).to eq('lock_version_required')
      expect(deal.reload.position).to eq(1000)
    end
  end

  describe 'reordering inside the same stage' do
    it 'does not create a stage transition' do
      # Force the deal (and its own creation transition) to exist before the measured block,
      # so a plain reorder is the only thing being asserted against.
      deal

      expect do
        patch move_url, params: { stage_id: origin_stage.id, position: 2000, lock_version: deal.lock_version },
                        headers: admin.create_new_auth_token, as: :json
      end.not_to change(Crm::StageTransition, :count)

      expect(response).to have_http_status(:success)
      expect(deal.reload.position).to eq(2000)
    end

    it 'does not restart stage_entered_at' do
      previous_stage_entered_at = deal.stage_entered_at

      patch move_url, params: { stage_id: origin_stage.id, position: 2000, lock_version: deal.lock_version },
                      headers: admin.create_new_auth_token, as: :json

      expect(deal.reload.stage_entered_at.to_i).to eq(previous_stage_entered_at.to_i)
    end

    # Reordering is a neutral operation: the move validations only guard a real stage change.
    it 'reorders a card inside a lost column without asking for the lost reason again' do
      lost_deal = create(:crm_deal, account: account, pipeline: pipeline, stage: lost_stage,
                                    status: :lost, lost_reason: lost_reason, position: 1000)

      patch "/api/v1/accounts/#{account.id}/crm/deals/#{lost_deal.id}/move",
            params: { stage_id: lost_stage.id, position: 2000, lock_version: lost_deal.lock_version },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(lost_deal.reload.position).to eq(2000)
      expect(lost_deal.status).to eq('lost')
      expect(lost_deal.lost_reason_id).to eq(lost_reason.id)
    end

    it 'reorders a card inside a full column without tripping the WIP limit' do
      full_stage = create(:crm_stage, account: account, pipeline: pipeline, position: 5, wip_limit: 1)
      full_stage_deal = create(:crm_deal, account: account, pipeline: pipeline, stage: full_stage, status: :open, position: 1000)

      patch "/api/v1/accounts/#{account.id}/crm/deals/#{full_stage_deal.id}/move",
            params: { stage_id: full_stage.id, position: 2000, lock_version: full_stage_deal.lock_version },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(full_stage_deal.reload.position).to eq(2000)
    end
  end

  describe 'status handling driven by the stage category' do
    it 'marks the deal as won and closes it' do
      patch move_url, params: { stage_id: won_stage.id, lock_version: deal.lock_version },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(deal.reload.status).to eq('won')
      expect(deal.closed_at).to be_present
      expect(response.parsed_body['status']).to eq('won')
    end

    it 'reopens the deal and clears closed_at and lost_reason_id when it goes back to an open stage' do
      patch move_url, params: { stage_id: lost_stage.id, lost_reason_id: lost_reason.id, lock_version: deal.lock_version },
                      headers: admin.create_new_auth_token, as: :json
      expect(deal.reload.status).to eq('lost')

      patch move_url, params: { stage_id: destination_stage.id, lock_version: deal.lock_version },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(deal.reload.status).to eq('open')
      expect(deal.closed_at).to be_nil
      expect(deal.lost_reason_id).to be_nil
    end
  end

  describe 'position handling' do
    it 'sends the card to the end of the destination column when no position is given' do
      create(:crm_deal, account: account, pipeline: pipeline, stage: destination_stage, position: 5000)

      patch move_url, params: { stage_id: destination_stage.id, lock_version: deal.lock_version },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(deal.reload.position).to eq(5000 + Crm::Deal::POSITION_GAP)
    end

    # An archived card is off the board, so it must not push new cards to the bottom.
    it 'ignores archived deals when computing the end of the destination column' do
      create(:crm_deal, account: account, pipeline: pipeline, stage: destination_stage, position: 5000)
      create(:crm_deal, account: account, pipeline: pipeline, stage: destination_stage, position: 90_000, archived_at: Time.current)

      patch move_url, params: { stage_id: destination_stage.id, lock_version: deal.lock_version },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(deal.reload.position).to eq(5000 + Crm::Deal::POSITION_GAP)
    end

    it 'respects the fractional position sent by the board' do
      patch move_url, params: { stage_id: destination_stage.id, position: 1500.5, lock_version: deal.lock_version },
                      headers: admin.create_new_auth_token, as: :json

      expect(deal.reload.position).to eq(BigDecimal('1500.5'))
    end
  end

  describe 'moving to a stage of another pipeline' do
    it 'returns not found' do
      other_pipeline = create(:crm_pipeline, account: account)
      other_pipeline_stage = create(:crm_stage, account: account, pipeline: other_pipeline)

      patch move_url, params: { stage_id: other_pipeline_stage.id, lock_version: deal.lock_version },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(deal.reload.stage_id).to eq(origin_stage.id)
    end

    it 'returns not found for a stage of another account' do
      foreign_stage = create(:crm_stage, account: other_account)

      patch move_url, params: { stage_id: foreign_stage.id, lock_version: deal.lock_version },
                      headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
