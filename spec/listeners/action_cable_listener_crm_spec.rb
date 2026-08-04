require 'rails_helper'

describe ActionCableListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:other_agent) { create(:user, account: account, role: :agent) }
  let!(:pipeline) { create(:crm_pipeline, account: account) }
  let!(:stage) { create(:crm_stage, account: account, pipeline: pipeline) }
  # `let!` on purpose: creating a deal dispatches `crm_deal.created` through the real dispatcher,
  # so the record has to exist before an example arms its expectation on the broadcast job.
  let!(:deal) { create(:crm_deal, account: account, pipeline: pipeline, stage: stage, owner: agent) }

  before do
    Current.user = nil
    Current.account = nil
  end

  describe '#crm_deal_created' do
    let(:event) { Events::Base.new(:'crm_deal.created', Time.zone.now, deal: deal) }

    it 'pushes the card to every agent and administrator of the account' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(admin.pubsub_token, agent.pubsub_token, other_agent.pubsub_token),
        'crm_deal.created',
        hash_including(id: deal.id, stage_id: stage.id, pipeline_id: pipeline.id, account_id: account.id)
      )

      listener.crm_deal_created(event)
    end

    it 'carries the fields the board card renders' do
      allow(ActionCableBroadcastJob).to receive(:perform_later)

      listener.crm_deal_created(event)

      expect(ActionCableBroadcastJob).to have_received(:perform_later).with(
        anything, 'crm_deal.created',
        hash_including(title: deal.title, position: deal.position, lock_version: deal.lock_version, status: 'open')
      )
    end
  end

  describe '#crm_deal_moved' do
    let(:event) { Events::Base.new(:'crm_deal.moved', Time.zone.now, deal: deal) }

    it 'broadcasts the move under its own event name' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        anything, 'crm_deal.moved', hash_including(id: deal.id)
      )

      listener.crm_deal_moved(event)
    end
  end

  describe '#crm_deal_updated' do
    let(:event) { Events::Base.new(:'crm_deal.updated', Time.zone.now, deal: deal) }

    it 'broadcasts the edited card' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        anything, 'crm_deal.updated', hash_including(id: deal.id)
      )

      listener.crm_deal_updated(event)
    end
  end

  describe '#crm_deal_archived' do
    let(:event) { Events::Base.new(:'crm_deal.archived', Time.zone.now, deal: deal) }

    before { deal.archive! }

    it 'broadcasts a card carrying archived_at, so the board can drop it' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        anything, 'crm_deal.archived', hash_including(id: deal.id, archived_at: deal.archived_at.to_i)
      )

      listener.crm_deal_archived(event)
    end
  end

  context 'when the pipeline restricts visibility by owner' do
    let!(:pipeline) { create(:crm_pipeline, :restricted_by_owner, account: account) }
    let(:event) { Events::Base.new(:'crm_deal.moved', Time.zone.now, deal: deal) }

    it 'does not push a deal owned by another agent' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(admin.pubsub_token, agent.pubsub_token),
        'crm_deal.moved',
        anything
      )

      listener.crm_deal_moved(event)
    end

    context 'when the deal has no owner' do
      let!(:deal) { create(:crm_deal, account: account, pipeline: pipeline, stage: stage, owner: nil) }

      it 'pushes to every agent, mirroring the policy exception for unassigned leads' do
        expect(ActionCableBroadcastJob).to receive(:perform_later).with(
          a_collection_containing_exactly(admin.pubsub_token, agent.pubsub_token, other_agent.pubsub_token),
          'crm_deal.moved',
          anything
        )

        listener.crm_deal_moved(event)
      end
    end

    context 'when the owner is an administrator' do
      let!(:deal) { create(:crm_deal, account: account, pipeline: pipeline, stage: stage, owner: admin) }

      it 'pushes to the administrators only, without duplicating the owner token' do
        expect(ActionCableBroadcastJob).to receive(:perform_later).with(
          [admin.pubsub_token], 'crm_deal.moved', anything
        )

        listener.crm_deal_moved(event)
      end
    end
  end

  describe '#crm_stage_positions_rebalanced' do
    let(:event) { Events::Base.new(:'crm_stage.positions_rebalanced', Time.zone.now, stage: stage) }

    it 'publishes only the stage, so no card a restricted agent cannot see travels' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(admin.pubsub_token, agent.pubsub_token, other_agent.pubsub_token),
        'crm_stage.positions_rebalanced',
        { stage_id: stage.id, pipeline_id: pipeline.id, account_id: account.id }
      )

      listener.crm_stage_positions_rebalanced(event)
    end
  end
end
