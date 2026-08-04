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

  describe '#regenerate_token!' do
    let(:source) { create(:crm_source, account: account) }

    it 'returns the plain token and stores only its digest' do
      token = source.regenerate_token!

      expect(token).to be_present
      expect(source.reload.token_digest).to eq(Digest::SHA256.hexdigest(token))
      expect(source.token_digest).not_to eq(token)
    end

    it 'changes the digest on every call, invalidating the previous token' do
      first_token = source.regenerate_token!
      first_digest = source.reload.token_digest

      second_token = source.regenerate_token!

      expect(second_token).not_to eq(first_token)
      expect(source.reload.token_digest).not_to eq(first_digest)
      expect(described_class.authenticate(account_id: account.id, token: first_token)).to be_nil
    end

    it 'flags the source as credentialed' do
      expect { source.regenerate_token! }.to change { source.reload.token? }.from(false).to(true)
    end
  end

  describe '.authenticate' do
    let(:source) { create(:crm_source, account: account, kind: :api) }
    let!(:token) { source.regenerate_token! }

    it 'resolves the source of a valid token' do
      expect(described_class.authenticate(account_id: account.id, token: token)).to eq(source)
    end

    it 'returns nothing for a token of another account' do
      expect(described_class.authenticate(account_id: create(:account).id, token: token)).to be_nil
    end

    it 'returns nothing for an unknown token' do
      expect(described_class.authenticate(account_id: account.id, token: 'not-a-token')).to be_nil
    end

    it 'returns nothing when no token is presented' do
      expect(described_class.authenticate(account_id: account.id, token: nil)).to be_nil
      expect(described_class.authenticate(account_id: account.id, token: '')).to be_nil
    end

    it 'ignores a source that was turned off' do
      source.update!(active: false)

      expect(described_class.authenticate(account_id: account.id, token: token)).to be_nil
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
