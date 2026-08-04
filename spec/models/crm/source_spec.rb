require 'rails_helper'

RSpec.describe Crm::Source do
  let(:account) { create(:account) }

  describe 'validations' do
    it 'requires a name' do
      source = build(:crm_source, account: account, name: nil)

      expect(source).not_to be_valid
      expect(source.errors[:name]).to be_present
    end

    it 'rejects a duplicate name within the same account' do
      existing = create(:crm_source, account: account)
      duplicate = build(:crm_source, account: account, name: existing.name)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to be_present
    end

    it 'allows the same name on another account' do
      existing = create(:crm_source, account: account)

      expect(build(:crm_source, account: create(:account), name: existing.name)).to be_valid
    end

    it 'rejects a duplicate identifier within the same account' do
      create(:crm_source, account: account, identifier: 'landing-black-friday')
      duplicate = build(:crm_source, account: account, identifier: 'landing-black-friday')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:identifier]).to be_present
    end

    it 'allows many sources without an identifier' do
      create(:crm_source, account: account, identifier: nil)

      expect(build(:crm_source, account: account, identifier: nil)).to be_valid
    end
  end

  describe 'scopes' do
    it 'splits sources between active and inactive' do
      active = create(:crm_source, account: account)
      inactive = create(:crm_source, :inactive, account: account)

      expect(described_class.active).to contain_exactly(active)
      expect(described_class.inactive).to contain_exactly(inactive)
    end
  end

  describe 'deals dependency' do
    it 'nullifies the source on its deals when destroyed' do
      source = create(:crm_source, account: account)
      deal = create(:crm_deal, account: account, source: source)

      source.destroy!

      expect(deal.reload.source_id).to be_nil
    end
  end
end
