class CreateCrmLostReasons < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_lost_reasons do |t|
      t.references :account, null: false, index: true, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps

      t.index [:account_id, :position]
    end
  end
end
