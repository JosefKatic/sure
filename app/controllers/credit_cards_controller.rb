class CreditCardsController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes(
    :id,
    :available_credit,
    :balance_is_remaining_credit,
    :minimum_payment,
    :apr,
    :annual_fee,
    :expiration_date
  )
end
