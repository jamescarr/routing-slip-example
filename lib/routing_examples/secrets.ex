defmodule RoutingExamples.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        RoutingExamples.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:routing_examples, :token_signing_secret)
  end
end
