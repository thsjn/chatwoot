require 'rails_helper'

RSpec.describe Crm::RebalanceStagePositionsJob do
  subject(:job) { described_class }

  let(:account) { create(:account) }
  let(:pipeline) { create(:crm_pipeline, account: account) }
  let(:stage) { create(:crm_stage, account: account, pipeline: pipeline) }
  let(:other_stage) { create(:crm_stage, account: account, pipeline: pipeline) }

  def deal_at(position, stage_record: stage, **attributes)
    create(:crm_deal, account: account, pipeline: pipeline, stage: stage_record, position: position, **attributes)
  end

  it 'rewrites the column as multiples of POSITION_GAP without changing the order' do
    first = deal_at(1000)
    second = deal_at(1000.5)
    third = deal_at(1000.75)
    fourth = deal_at(2000)

    job.perform_now(stage.id)

    expect(Crm::Deal.where(stage_id: stage.id).ordered.pluck(:id)).to eq([first.id, second.id, third.id, fourth.id])
    expect(Crm::Deal.where(stage_id: stage.id).ordered.pluck(:position)).to eq([1000, 2000, 3000, 4000])
  end

  # The whole point of the rewrite is that nothing the user can see changed, so an open board must
  # not be told its cards are stale: bumping `lock_version` would turn the next drag of every card
  # of the column into a 409 over a housekeeping write nobody asked for.
  it 'does not touch lock_version' do
    deal = deal_at(1000.25)
    versions = Crm::Deal.where(stage_id: stage.id).pluck(:lock_version)

    job.perform_now(stage.id)

    expect(Crm::Deal.where(stage_id: stage.id).pluck(:lock_version)).to eq(versions)
    expect { deal.reload }.not_to change(deal, :lock_version)
  end

  it 'leaves the other columns alone' do
    untouched = deal_at(1500.5, stage_record: other_stage)

    deal_at(1000)
    job.perform_now(stage.id)

    expect(untouched.reload.position).to eq(1500.5)
  end

  it 'skips archived cards, which are off the board' do
    archived = deal_at(1000.25, archived_at: Time.current)
    active = deal_at(1000.5)

    job.perform_now(stage.id)

    expect(archived.reload.position).to eq(1000.25)
    expect(active.reload.position).to eq(1000)
  end

  it 'tells the open boards to resync the column' do
    deal_at(1000)
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

    job.perform_now(stage.id)

    expect(Rails.configuration.dispatcher).to have_received(:dispatch).with('crm_stage.positions_rebalanced', anything, stage: stage)
  end

  it 'does nothing for an empty column' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

    job.perform_now(stage.id)

    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with('crm_stage.positions_rebalanced', anything, anything)
  end

  it 'is a no-op for a stage that no longer exists' do
    expect { job.perform_now(0) }.not_to raise_error
  end
end
