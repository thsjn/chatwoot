require 'rails_helper'

RSpec.describe Crm::MoveDealService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { create(:crm_pipeline, account: account) }
  let(:stage) { create(:crm_stage, account: account, pipeline: pipeline, position: 0) }
  let(:next_stage) { create(:crm_stage, account: account, pipeline: pipeline, position: 1) }

  def deal_at(position, stage_record: stage)
    create(:crm_deal, account: account, pipeline: pipeline, stage: stage_record, position: position)
  end

  def move(deal, to_stage, position)
    described_class.new(deal: deal, stage: to_stage, user: user, position: position, lock_version: deal.lock_version).perform
  end

  describe 'position rebalancing' do
    it 'does not schedule a rebalance while the column still has room' do
      deal_at(1000)
      deal_at(2000)
      moved = deal_at(3000)

      expect { move(moved, stage, 1500) }.not_to have_enqueued_job(Crm::RebalanceStagePositionsJob)
    end

    # Fractional indexing halves the interval on every drop into it: this is the drop that lands
    # closer to its neighbour than the threshold and leaves the column with no room to split again.
    it 'schedules a rebalance when the card lands under the convergence threshold' do
      deal_at(1000)
      deal_at(1001)
      moved = deal_at(5000)

      expect { move(moved, stage, 1000.5) }.to have_enqueued_job(Crm::RebalanceStagePositionsJob).with(stage.id)
    end

    it 'schedules the rebalance for the destination column of a cross stage move' do
      deal_at(1000, stage_record: next_stage)
      deal_at(1000.25, stage_record: next_stage)
      moved = deal_at(1000)

      expect { move(moved, next_stage, 1000.5) }.to have_enqueued_job(Crm::RebalanceStagePositionsJob).with(next_stage.id)
    end

    it 'ignores archived cards when measuring the gap' do
      deal_at(1000)
      create(:crm_deal, account: account, pipeline: pipeline, stage: stage, position: 1000.25, archived_at: Time.current)
      moved = deal_at(5000)

      expect { move(moved, stage, 3000) }.not_to have_enqueued_job(Crm::RebalanceStagePositionsJob)
    end

    it 'does not schedule anything when the move is rejected' do
      stage.update!(wip_limit: 1)
      deal_at(1000, stage_record: stage)
      moved = deal_at(1000.1, stage_record: next_stage)

      expect do
        expect { move(moved, stage, 1000.05) }.to raise_error(described_class::MoveError)
      end.not_to have_enqueued_job(Crm::RebalanceStagePositionsJob)
    end
  end

  describe '.positions_converging?' do
    it 'reports a column whose neighbours are further apart than the threshold' do
      deal_at(1000)
      deal_at(2000)

      expect(Crm::Deal.positions_converging?(stage.id)).to be(false)
    end

    it 'reports a column whose neighbours no longer have a whole unit between them' do
      deal_at(1000)
      deal_at(1000.4)

      expect(Crm::Deal.positions_converging?(stage.id)).to be(true)
    end

    it 'reports a column holding a single card as having room' do
      deal_at(1000)

      expect(Crm::Deal.positions_converging?(stage.id)).to be(false)
    end
  end
end
