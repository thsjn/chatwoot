require 'rails_helper'

RSpec.describe Crm::StageTransition do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:pipeline) { create(:crm_pipeline, account: account) }
  let(:from_stage) { create(:crm_stage, account: account, pipeline: pipeline) }
  let(:to_stage) { create(:crm_stage, account: account, pipeline: pipeline) }
  let(:deal) { create(:crm_deal, account: account, pipeline: pipeline, stage: from_stage) }

  describe 'validations' do
    it 'is valid with stages and a user from the deal account' do
      transition = build(
        :crm_stage_transition,
        deal: deal,
        from_stage: from_stage,
        to_stage: to_stage,
        user: create(:user, account: account, role: :agent)
      )

      expect(transition).to be_valid
    end

    it 'is valid without a from_stage and without a user' do
      expect(build(:crm_stage_transition, deal: deal, from_stage: nil, to_stage: to_stage, user: nil)).to be_valid
    end

    it 'requires a to_stage' do
      transition = build(:crm_stage_transition, deal: deal)
      transition.to_stage = nil

      expect(transition).not_to be_valid
      expect(transition.errors[:to_stage]).to be_present
    end
  end

  describe 'cross account isolation' do
    let(:foreign_stage) { create(:crm_stage, account: other_account, pipeline: create(:crm_pipeline, account: other_account)) }

    it 'rejects a from_stage from another account' do
      transition = build(:crm_stage_transition, deal: deal, from_stage: foreign_stage, to_stage: to_stage)

      expect(transition).not_to be_valid
      expect(transition.errors[:from_stage_id]).to include('must belong to the same account as the deal')
    end

    it 'rejects a to_stage from another account' do
      transition = build(:crm_stage_transition, deal: deal, to_stage: foreign_stage)

      expect(transition).not_to be_valid
      expect(transition.errors[:to_stage_id]).to include('must belong to the same account as the deal')
    end

    it 'rejects a user who is not a member of the deal account' do
      transition = build(:crm_stage_transition, deal: deal, to_stage: to_stage, user: create(:user, account: other_account, role: :agent))

      expect(transition).not_to be_valid
      expect(transition.errors[:user_id]).to include('must be a member of the same account as the deal')
    end
  end

  describe 'scopes' do
    it 'splits transitions between automated and manual' do
      # Instantiating `deal` already wrote its own creation transition (`automated: false`,
      # see `Crm::Deal#record_creation_transition`), so it belongs in the `manual` scope too.
      creation_transition = deal.stage_transitions.sole
      automated = create(:crm_stage_transition, :by_automation, deal: deal, to_stage: to_stage)
      manual = create(:crm_stage_transition, deal: deal, to_stage: to_stage)

      expect(described_class.automated).to contain_exactly(automated)
      expect(described_class.manual).to contain_exactly(creation_transition, manual)
    end
  end
end
