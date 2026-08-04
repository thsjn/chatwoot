# == Schema Information
#
# Table name: crm_sources
#
#  id           :bigint           not null, primary key
#  active       :boolean          default(TRUE), not null
#  identifier   :string
#  kind         :integer          default("inbox"), not null
#  name         :string           not null
#  token_digest :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  inbox_id     :bigint
#
# Indexes
#
#  index_crm_sources_on_account_id                 (account_id)
#  index_crm_sources_on_account_id_and_identifier  (account_id,identifier)
#  index_crm_sources_on_account_id_and_kind        (account_id,kind)
#  index_crm_sources_on_inbox_id                   (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => nullify
#
class Crm::Source < ApplicationRecord
  self.table_name = 'crm_sources'

  belongs_to :account
  belongs_to :inbox, optional: true
  has_many :deals, class_name: 'Crm::Deal', foreign_key: :source_id, dependent: :nullify, inverse_of: :source

  # `_prefix` is mandatory here: the `inbox` value would otherwise clash with the
  # `belongs_to :inbox` association and `api`/`import` read poorly without it.
  enum kind: { inbox: 0, landing: 1, import: 2, api: 3, n8n: 4, manual: 5 }, _prefix: true

  validates :name, presence: true
  validates :name, uniqueness: { scope: :account_id }
  validates :identifier, uniqueness: { scope: :account_id }, allow_blank: true

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :with_token, -> { where.not(token_digest: nil) }

  # Same generator `has_secure_token` uses across the app (`AccessToken#token`, `Channel::Api#hmac_token`,
  # `Integrations::Hook#access_token`): a base58 random string, which is URL/header safe and has no
  # ambiguous characters to mistype. The length is bumped from the Rails default of 24 because this
  # one is a bearer credential handed to third parties (landing pages, n8n) and is never rotated
  # automatically.
  TOKEN_LENGTH = 32

  # Unlike those, the plain token is NOT stored: the column is a digest, so a database dump does not
  # hand over working credentials. That is also why the value is only ever returned by the endpoint
  # that generates it.
  def self.digest_token(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  # Resolves the source a presented token belongs to, inside ONE account. Scoping by account is what
  # makes a valid token of another account behave exactly like an invalid one.
  #
  # The candidates are compared in constant time instead of being looked up with a
  # `where(token_digest: ...)`: the set is the handful of credentialed sources of a single account,
  # so the loop costs nothing and the response time does not depend on how many leading bytes of the
  # digest matched.
  def self.authenticate(account_id:, token:)
    return if token.blank?

    digest = digest_token(token)

    where(account_id: account_id).active.with_token.find do |source|
      ActiveSupport::SecurityUtils.secure_compare(source.token_digest, digest)
    end
  end

  # Returns the plain token: the ONLY moment it exists outside the caller that receives it.
  # Regenerating overwrites the digest, so the previous token stops authenticating immediately.
  def regenerate_token!
    token = SecureRandom.base58(TOKEN_LENGTH)
    update!(token_digest: self.class.digest_token(token))
    token
  end

  def token?
    token_digest.present?
  end
end
