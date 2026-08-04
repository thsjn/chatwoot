require 'rails_helper'

RSpec.describe Crm::Pipeline do
  let(:account) { create(:account) }

  describe 'validations' do
    it 'requires a name' do
      pipeline = build(:crm_pipeline, account: account, name: nil)

      expect(pipeline).not_to be_valid
      expect(pipeline.errors[:name]).to be_present
    end

    it 'rejects a duplicate name within the same account' do
      existing = create(:crm_pipeline, account: account)
      duplicate = build(:crm_pipeline, account: account, name: existing.name)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to be_present
    end

    it 'allows the same name on a different account' do
      existing = create(:crm_pipeline, account: account)

      expect(build(:crm_pipeline, account: create(:account), name: existing.name)).to be_valid
    end
  end

  # Marking a funnel as the default takes the flag away from the previous one instead of being
  # refused: the switch on the administration screen is a single step.
  describe 'default pipeline swap' do
    it 'takes the default away from the previous pipeline when another one is marked' do
      previous = create(:crm_pipeline, :default, account: account)
      other = create(:crm_pipeline, account: account)

      other.update!(is_default: true)

      expect(other.reload.is_default).to be(true)
      expect(previous.reload.is_default).to be(false)
    end

    it 'takes the default away from the previous pipeline when a new default is created' do
      previous = create(:crm_pipeline, :default, account: account)

      created = create(:crm_pipeline, :default, account: account)

      expect(created.reload.is_default).to be(true)
      expect(previous.reload.is_default).to be(false)
    end

    # `index_crm_pipelines_on_account_id_default` is a partial UNIQUE index, so the account is
    # never left holding two defaults — not even for the instant between the two writes.
    it 'never leaves the account with more than one default' do
      create(:crm_pipeline, :default, account: account)
      create(:crm_pipeline, :default, account: account)
      create(:crm_pipeline, account: account).update!(is_default: true)

      expect(described_class.where(account_id: account.id, is_default: true).count).to eq(1)
    end

    it 'leaves the default of another account untouched' do
      foreign_default = create(:crm_pipeline, :default, account: create(:account))

      create(:crm_pipeline, :default, account: account)

      expect(foreign_default.reload.is_default).to be(true)
    end

    # The swap only runs when the flag actually changes, so re-saving the current default must not
    # clear the row it is about to write.
    it 'keeps the flag when the current default is saved again' do
      default_pipeline = create(:crm_pipeline, :default, account: account)

      default_pipeline.update!(name: 'Comercial 2026')

      expect(default_pipeline.reload.is_default).to be(true)
    end

    it 'allows a default pipeline per account' do
      create(:crm_pipeline, :default, account: account)

      expect(build(:crm_pipeline, :default, account: create(:account))).to be_valid
    end

    it 'allows many non default pipelines on the same account' do
      create(:crm_pipeline, :default, account: account)

      expect(build(:crm_pipeline, account: account)).to be_valid
    end
  end

  describe 'archiving' do
    let!(:active_pipeline) { create(:crm_pipeline, account: account) }
    let!(:archived_pipeline) { create(:crm_pipeline, :archived, account: account) }

    it 'splits pipelines between the active and archived scopes' do
      expect(described_class.active).to contain_exactly(active_pipeline)
      expect(described_class.archived).to contain_exactly(archived_pipeline)
    end

    it 'moves a pipeline between the scopes' do
      active_pipeline.archive!
      expect(active_pipeline).to be_archived
      expect(described_class.active).not_to include(active_pipeline)

      active_pipeline.unarchive!
      expect(active_pipeline).not_to be_archived
      expect(described_class.active).to include(active_pipeline)
    end
  end

  describe '#entry_stage' do
    let(:pipeline) { create(:crm_pipeline, account: account) }

    it 'returns the stage flagged as entry' do
      create(:crm_stage, account: account, pipeline: pipeline, position: 0)
      entry = create(:crm_stage, :entry, account: account, pipeline: pipeline, position: 10)

      expect(pipeline.entry_stage).to eq(entry)
    end

    it 'falls back to the first stage by position when no entry stage exists' do
      first = create(:crm_stage, account: account, pipeline: pipeline, position: 1)
      create(:crm_stage, account: account, pipeline: pipeline, position: 2)

      expect(pipeline.entry_stage).to eq(first)
    end
  end

  describe 'deals dependency' do
    it 'refuses to destroy a pipeline that still has deals' do
      pipeline = create(:crm_pipeline, account: account)
      create(:crm_deal, account: account, pipeline: pipeline)

      expect(pipeline.destroy).to be(false)
      expect(pipeline.errors[:base]).to be_present
    end

    # Rails runs the `dependent:` callbacks in declaration order, so the restrictive `deals`
    # association has to be declared before the `destroy_async` on `stages`.
    it 'does not enqueue the async destruction of the stages when the destroy is refused' do
      pipeline = create(:crm_pipeline, account: account)
      stage = create(:crm_stage, account: account, pipeline: pipeline)
      create(:crm_deal, account: account, pipeline: pipeline, stage: stage)

      expect { pipeline.destroy }.not_to have_enqueued_job(ActiveRecord::DestroyAssociationAsyncJob)
      expect(Crm::Stage.exists?(stage.id)).to be(true)
    end
  end
end
