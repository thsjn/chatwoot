require 'rails_helper'

RSpec.describe Crm::LostReason do
  let(:account) { create(:account) }

  describe 'validations' do
    it 'requires a name' do
      lost_reason = build(:crm_lost_reason, account: account, name: nil)

      expect(lost_reason).not_to be_valid
      expect(lost_reason.errors[:name]).to be_present
    end

    it 'rejects a duplicate name within the same account' do
      existing = create(:crm_lost_reason, account: account)
      duplicate = build(:crm_lost_reason, account: account, name: existing.name)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to be_present
    end

    it 'allows the same name on another account' do
      existing = create(:crm_lost_reason, account: account)

      expect(build(:crm_lost_reason, account: create(:account), name: existing.name)).to be_valid
    end
  end

  describe 'scopes' do
    it 'splits reasons between active and inactive' do
      active = create(:crm_lost_reason, account: account)
      inactive = create(:crm_lost_reason, :inactive, account: account)

      expect(described_class.active).to contain_exactly(active)
      expect(described_class.inactive).to contain_exactly(inactive)
    end

    it 'orders reasons by position' do
      second = create(:crm_lost_reason, account: account, position: 2)
      first = create(:crm_lost_reason, account: account, position: 1)

      expect(described_class.ordered).to eq([first, second])
    end
  end

  describe 'deals dependency' do
    it 'nullifies the lost reason on its deals when destroyed' do
      lost_reason = create(:crm_lost_reason, account: account)
      deal = create(:crm_deal, :lost, account: account, lost_reason: lost_reason)

      lost_reason.destroy!

      expect(deal.reload.lost_reason_id).to be_nil
    end
  end
end
