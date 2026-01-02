defmodule RoutingExamples.Accounts do
  use Ash.Domain, otp_app: :routing_examples, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource RoutingExamples.Accounts.Token
    resource RoutingExamples.Accounts.User
  end
end
