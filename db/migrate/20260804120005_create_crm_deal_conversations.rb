class CreateCrmDealConversations < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_deal_conversations do |t|
      t.references :deal, null: false, index: true, foreign_key: { to_table: :crm_deals, on_delete: :cascade }
      t.references :conversation, null: false, index: true, foreign_key: { on_delete: :cascade }
      t.boolean :is_origin, null: false, default: false

      t.timestamps

      t.index [:deal_id, :conversation_id], unique: true, name: 'index_crm_deal_conversations_on_deal_and_conversation'
    end
  end
end
