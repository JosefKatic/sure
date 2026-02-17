class AddBalanceIsRemainingCreditToCreditCards < ActiveRecord::Migration[7.2]
  def change
    add_column :credit_cards, :balance_is_remaining_credit, :boolean, default: false, null: false
  end
end
