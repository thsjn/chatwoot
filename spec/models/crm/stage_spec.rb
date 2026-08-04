require 'rails_helper'

RSpec.describe Crm::Stage do
  let(:account) { create(:account) }
  let(:pipeline) { create(:crm_pipeline, account: account) }

  describe 'validations' do
    it 'requires a name' do
      stage = build(:crm_stage, account: account, pipeline: pipeline, name: nil)

      expect(stage).not_to be_valid
      expect(stage.errors[:name]).to be_present
    end

    it 'rejects a duplicate name within the same pipeline' do
      existing = create(:crm_stage, account: account, pipeline: pipeline)
      duplicate = build(:crm_stage, account: account, pipeline: pipeline, name: existing.name)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to be_present
    end

    it 'allows the same name on another pipeline' do
      existing = create(:crm_stage, account: account, pipeline: pipeline)
      other_pipeline = create(:crm_pipeline, account: account)

      expect(build(:crm_stage, account: account, pipeline: other_pipeline, name: existing.name)).to be_valid
    end
  end

  describe 'color token' do
    it 'accepts every token of the closed list' do
      described_class::COLORS.each do |color|
        expect(build(:crm_stage, account: account, pipeline: pipeline, color: color)).to be_valid
      end
    end

    it 'allows no color' do
      expect(build(:crm_stage, account: account, pipeline: pipeline, color: nil)).to be_valid
    end

    it 'rejects a hex value' do
      stage = build(:crm_stage, account: account, pipeline: pipeline, color: '#ff0000')

      expect(stage).not_to be_valid
      expect(stage.errors[:color]).to be_present
    end
  end

  describe 'probability range' do
    it 'accepts the boundaries' do
      expect(build(:crm_stage, account: account, pipeline: pipeline, probability: 0)).to be_valid
      expect(build(:crm_stage, account: account, pipeline: pipeline, probability: 100)).to be_valid
    end

    it 'rejects a probability below zero' do
      stage = build(:crm_stage, account: account, pipeline: pipeline, probability: -1)

      expect(stage).not_to be_valid
      expect(stage.errors[:probability]).to be_present
    end

    it 'rejects a probability above one hundred' do
      stage = build(:crm_stage, account: account, pipeline: pipeline, probability: 101)

      expect(stage).not_to be_valid
      expect(stage.errors[:probability]).to be_present
    end
  end

  describe 'rotting_days and wip_limit' do
    it 'allows nil for both' do
      expect(build(:crm_stage, account: account, pipeline: pipeline, rotting_days: nil, wip_limit: nil)).to be_valid
    end

    it 'rejects a non positive rotting_days' do
      stage = build(:crm_stage, account: account, pipeline: pipeline, rotting_days: 0)

      expect(stage).not_to be_valid
      expect(stage.errors[:rotting_days]).to be_present
    end

    it 'rejects a non positive wip_limit' do
      stage = build(:crm_stage, account: account, pipeline: pipeline, wip_limit: 0)

      expect(stage).not_to be_valid
      expect(stage.errors[:wip_limit]).to be_present
    end
  end

  describe 'cross account isolation' do
    it 'rejects a pipeline from another account' do
      stage = build(:crm_stage, account: account, pipeline: create(:crm_pipeline, account: create(:account)))

      expect(stage).not_to be_valid
      expect(stage.errors[:pipeline_id]).to include('must belong to the same account as the stage')
    end
  end

  describe '#closing?' do
    it 'is true for won and lost categories' do
      expect(build(:crm_stage, :won, account: account, pipeline: pipeline)).to be_closing
      expect(build(:crm_stage, :lost, account: account, pipeline: pipeline)).to be_closing
    end

    it 'is false for open stages' do
      expect(build(:crm_stage, account: account, pipeline: pipeline)).not_to be_closing
    end
  end

  describe '#wip_exceeded?' do
    let(:stage) { create(:crm_stage, account: account, pipeline: pipeline, wip_limit: 1) }

    it 'is false when the limit is not set' do
      unlimited = create(:crm_stage, account: account, pipeline: pipeline, wip_limit: nil)
      create(:crm_deal, account: account, pipeline: pipeline, stage: unlimited)

      expect(unlimited).not_to be_wip_exceeded
    end

    it 'is true once the open active deals reach the limit' do
      create(:crm_deal, account: account, pipeline: pipeline, stage: stage)

      expect(stage).to be_wip_exceeded
    end

    it 'ignores archived and closed deals' do
      create(:crm_deal, :archived, account: account, pipeline: pipeline, stage: stage)
      create(:crm_deal, :won, account: account, pipeline: pipeline, stage: stage)

      expect(stage).not_to be_wip_exceeded
    end
  end
end
