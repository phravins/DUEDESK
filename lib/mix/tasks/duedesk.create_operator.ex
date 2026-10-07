defmodule Mix.Tasks.Duedesk.CreateOperator do
  @shortdoc "Creates an internal operator for the /admin console"

  @moduledoc """
  Creates an operator with a generated password, printed once.

      mix duedesk.create_operator ops@duedesk.in "Ops Name"
  """
  use Mix.Task

  @impl true
  def run([email, name]) do
    Mix.Task.run("app.start")
    password = :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)

    case DueDesk.Admin.create_operator(%{email: email, name: name, password: password}) do
      {:ok, operator} ->
        Mix.shell().info("Operator #{operator.email} created.")
        Mix.shell().info("Password (shown once, store it in your password manager): #{password}")

      {:error, changeset} ->
        Mix.raise("Could not create operator: #{inspect(changeset.errors)}")
    end
  end

  def run(_), do: Mix.raise(~s(usage: mix duedesk.create_operator EMAIL "NAME"))
end
