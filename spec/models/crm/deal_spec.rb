require 'rails_helper'

RSpec.describe Crm::Deal do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:pipeline) { create(:crm_pipeline, account: account) }
  let(:stage) { create(:crm_stage, account: account, pipeline: pipeline) }

  describe 'validations' do
    it 'is valid with the factory defaults' do
      expect(build(:crm_deal, account: account)).to be_valid
    end

    it 'requires a title' do
      deal = build(:crm_deal, account: account, title: nil)

      expect(deal).not_to be_valid
      expect(deal.errors[:title]).to be_present
    end

    it 'requires a currency' do
      deal = build(:crm_deal, account: account, currency: nil)

      expect(deal).not_to be_valid
      expect(deal.errors[:currency]).to be_present
    end

    it 'rejects a negative value_cents' do
      deal = build(:crm_deal, account: account, value_cents: -1)

      expect(deal).not_to be_valid
      expect(deal.errors[:value_cents]).to be_present
    end
  end

  describe 'cross account isolation' do
    it 'rejects a stage from another pipeline of the same account' do
      foreign_pipeline = create(:crm_pipeline, account: account)
      foreign_stage = create(:crm_stage, account: account, pipeline: foreign_pipeline)
      deal = build(:crm_deal, account: account, pipeline: pipeline, stage: foreign_stage)

      expect(deal).not_to be_valid
      expect(deal.errors[:stage_id]).to include('must belong to the pipeline of the deal')
    end

    it 'rejects a pipeline from another account' do
      foreign_pipeline = create(:crm_pipeline, account: other_account)
      foreign_stage = create(:crm_stage, account: other_account, pipeline: foreign_pipeline)
      deal = build(:crm_deal, account: account, pipeline: foreign_pipeline, stage: foreign_stage)

      expect(deal).not_to be_valid
      expect(deal.errors[:pipeline_id]).to include('must belong to the same account as the deal')
    end

    it 'rejects a contact from another account' do
      deal = build(:crm_deal, account: account, contact: create(:contact, account: other_account))

      expect(deal).not_to be_valid
      expect(deal.errors[:contact_id]).to include('must belong to the same account as the deal')
    end

    it 'rejects an owner who is not a member of the account' do
      deal = build(:crm_deal, account: account, owner: create(:user, account: other_account, role: :agent))

      expect(deal).not_to be_valid
      expect(deal.errors[:owner_id]).to include('must be a member of the same account as the deal')
    end

    it 'accepts an owner who is a member of the account' do
      expect(build(:crm_deal, account: account, owner: create(:user, account: account, role: :agent))).to be_valid
    end

    it 'rejects a team from another account' do
      deal = build(:crm_deal, account: account, team: create(:team, account: other_account))

      expect(deal).not_to be_valid
      expect(deal.errors[:team_id]).to include('must belong to the same account as the deal')
    end

    it 'rejects a source from another account' do
      deal = build(:crm_deal, account: account, source: create(:crm_source, account: other_account))

      expect(deal).not_to be_valid
      expect(deal.errors[:source_id]).to include('must belong to the same account as the deal')
    end

    it 'rejects a source inbox from another account' do
      deal = build(:crm_deal, account: account, source_inbox: create(:inbox, account: other_account))

      expect(deal).not_to be_valid
      expect(deal.errors[:source_inbox_id]).to include('must belong to the same account as the deal')
    end

    it 'rejects a lost reason from another account' do
      deal = build(:crm_deal, account: account, lost_reason: create(:crm_lost_reason, account: other_account))

      expect(deal).not_to be_valid
      expect(deal.errors[:lost_reason_id]).to include('must belong to the same account as the deal')
    end

    it 'accepts optional references from the same account' do
      deal = build(
        :crm_deal,
        account: account,
        team: create(:team, account: account),
        source: create(:crm_source, account: account),
        source_inbox: create(:inbox, account: account),
        lost_reason: create(:crm_lost_reason, account: account)
      )

      expect(deal).to be_valid
    end
  end

  describe 'stage_entered_at' do
    it 'is filled on creation' do
      freeze_time do
        expect(create(:crm_deal, account: account).stage_entered_at).to eq(Time.current)
      end
    end

    it 'keeps an explicitly provided value' do
      entered_at = 3.days.ago.change(usec: 0)

      expect(create(:crm_deal, account: account, stage_entered_at: entered_at).stage_entered_at).to eq(entered_at)
    end
  end

  describe '.rotting' do
    let(:rotting_stage) { create(:crm_stage, account: account, pipeline: pipeline, rotting_days: 3) }
    let(:evergreen_stage) { create(:crm_stage, account: account, pipeline: pipeline, rotting_days: nil) }

    it 'returns deals sitting in the stage longer than rotting_days' do
      rotten = create(:crm_deal, account: account, pipeline: pipeline, stage: rotting_stage, stage_entered_at: 5.days.ago)
      create(:crm_deal, account: account, pipeline: pipeline, stage: rotting_stage, stage_entered_at: 1.day.ago)

      expect(described_class.rotting).to contain_exactly(rotten)
    end

    it 'ignores stages without a rotting_days limit' do
      create(:crm_deal, account: account, pipeline: pipeline, stage: evergreen_stage, stage_entered_at: 90.days.ago)

      expect(described_class.rotting).to be_empty
    end

    it 'ignores archived and closed deals' do
      create(:crm_deal, :archived, account: account, pipeline: pipeline, stage: rotting_stage, stage_entered_at: 5.days.ago)
      create(:crm_deal, :won, account: account, pipeline: pipeline, stage: rotting_stage, stage_entered_at: 5.days.ago)
      create(:crm_deal, :lost, account: account, pipeline: pipeline, stage: rotting_stage, stage_entered_at: 5.days.ago)

      expect(described_class.rotting).to be_empty
    end
  end

  describe 'archiving' do
    let!(:active_deal) { create(:crm_deal, account: account, pipeline: pipeline, stage: stage) }
    let!(:archived_deal) { create(:crm_deal, :archived, account: account, pipeline: pipeline, stage: stage) }

    it 'splits deals between the active and archived scopes' do
      expect(described_class.active).to contain_exactly(active_deal)
      expect(described_class.archived).to contain_exactly(archived_deal)
    end

    it 'moves a deal between the scopes' do
      active_deal.archive!
      expect(active_deal).to be_archived
      expect(described_class.active).not_to include(active_deal)

      active_deal.unarchive!
      expect(active_deal).not_to be_archived
      expect(described_class.active).to include(active_deal)
    end
  end

  describe '#value' do
    it 'converts cents to the currency unit' do
      expect(build(:crm_deal, account: account, value_cents: 123_456).value).to eq(1234.56)
    end
  end

  describe '#origin_conversation' do
    let(:deal) { create(:crm_deal, account: account) }

    it 'returns only the conversation flagged as origin' do
      create(:crm_deal_conversation, deal: deal)
      origin = create(:crm_deal_conversation, :origin, deal: deal)

      expect(deal.origin_conversation).to eq(origin.conversation)
    end

    it 'returns nil when no conversation is flagged as origin' do
      create(:crm_deal_conversation, deal: deal)

      expect(deal.origin_conversation).to be_nil
    end
  end

  describe '#next_activity_at' do
    let(:deal) { create(:crm_deal, account: account, pipeline: pipeline, stage: stage) }

    it 'returns the earliest open activity due in the future' do
      create(:crm_activity, :task, account: account, deal: deal, due_at: 5.days.from_now)
      next_task = create(:crm_activity, :task, account: account, deal: deal, due_at: 2.days.from_now)

      expect(deal.next_activity_at).to be_within(1.second).of(next_task.due_at)
    end

    it 'ignores overdue, completed and undated activities' do
      create(:crm_activity, :task, account: account, deal: deal, due_at: 1.day.ago)
      create(:crm_activity, :task, :completed, account: account, deal: deal, due_at: 1.day.from_now)
      create(:crm_activity, account: account, deal: deal, due_at: nil)

      expect(deal.next_activity_at).to be_nil
    end

    it 'resolves the same value from the listing scope without loading the activities' do
      next_task = create(:crm_activity, :task, account: account, deal: deal, due_at: 2.days.from_now)
      create(:crm_activity, :task, account: account, deal: deal, due_at: 1.day.ago)

      loaded = described_class.with_next_activity.find(deal.id)

      expect(loaded.next_activity_at).to be_within(1.second).of(next_task.due_at)
      expect(loaded.activities).not_to be_loaded
    end
  end

  describe 'optimistic locking' do
    it 'raises when a stale copy is saved' do
      deal = create(:crm_deal, account: account)
      stale_copy = described_class.find(deal.id)
      deal.update!(position: 10)

      expect { stale_copy.update!(position: 20) }.to raise_error(ActiveRecord::StaleObjectError)
    end
  end
end
