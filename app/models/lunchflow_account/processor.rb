class LunchflowAccount::Processor
  include CurrencyNormalizable

  attr_reader :lunchflow_account

  def initialize(lunchflow_account)
    @lunchflow_account = lunchflow_account
  end

  def process
    unless lunchflow_account.current_account.present?
      Rails.logger.info "LunchflowAccount::Processor - No linked account for lunchflow_account #{lunchflow_account.id}, skipping processing"
      return
    end

    Rails.logger.info "LunchflowAccount::Processor - Processing lunchflow_account #{lunchflow_account.id} (account #{lunchflow_account.account_id})"

    begin
      process_account!
    rescue StandardError => e
      Rails.logger.error "LunchflowAccount::Processor - Failed to process account #{lunchflow_account.id}: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.join("\n")}"
      report_exception(e, "account")
      raise
    end

    process_transactions
    process_investments
  end

  private

    def process_account!
      if lunchflow_account.current_account.blank?
        Rails.logger.error("Lunchflow account #{lunchflow_account.id} has no associated Account")
        return
      end

      # Update account balance from latest Lunchflow data
      account = lunchflow_account.current_account
      balance = lunchflow_account.current_balance || 0

      # Credit cards: when "balance is remaining credit" is enabled, the provider sends "remaining to spend"
      # (e.g. 17899) instead of debt. We store debt (amount owed). Convert: debt = limit - remaining.
      # When checkbox is off, pass through as-is (Lunchflow sends positive = debt, same as our app).
      # Loans: provider returns inverted signs, so negate.
      # Other account types (depository, etc.): pass through as-is.
      if account.accountable_type == "CreditCard" && account.credit_card.balance_is_remaining_credit?
        limit = account.credit_card.available_credit
        if limit.present? && limit.to_d > 0
          balance = limit.to_d - balance
        end
      elsif account.accountable_type == "CreditCard" || account.accountable_type == "Loan"
        balance = -balance
      end

      # Normalize currency with fallback chain: parsed lunchflow currency -> existing account currency -> USD
      currency = parse_currency(lunchflow_account.currency) || account.currency || "USD"
      
      # Update account balance
      account.update!(
        balance: balance,
        cash_balance: balance,
        currency: currency
      )
    end

    def process_transactions
      LunchflowAccount::Transactions::Processor.new(lunchflow_account).process
    rescue => e
      report_exception(e, "transactions")
    end

    def process_investments
      # Only process holdings for investment/crypto accounts with holdings support
      return unless lunchflow_account.holdings_supported?
      return unless [ "Investment", "Crypto" ].include?(lunchflow_account.current_account&.accountable_type)

      LunchflowAccount::Investments::HoldingsProcessor.new(lunchflow_account).process
    rescue => e
      report_exception(e, "holdings")
    end

    def report_exception(error, context)
      Sentry.capture_exception(error) do |scope|
        scope.set_tags(
          lunchflow_account_id: lunchflow_account.id,
          context: context
        )
      end
    end
end
