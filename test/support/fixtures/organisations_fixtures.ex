defmodule DueDesk.OrganisationsFixtures do
  @moduledoc """
  Test helpers for Organisations.
  """

  alias DueDesk.Organisations

  @doc "A Udyam number no other test uses."
  def unique_udyam do
    digits =
      System.unique_integer([:positive])
      |> rem(10_000_000)
      |> Integer.to_string()
      |> String.pad_leading(7, "0")

    "UDYAM-MH-01-#{digits}"
  end

  def valid_organisation_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Org #{System.unique_integer([:positive])}",
      type: "proprietorship",
      identifier: unique_udyam(),
      declaration_accepted: true
    })
  end

  @doc "Creates an Organisation in the scope's account."
  def organisation_fixture(scope, attrs \\ %{}) do
    {:ok, organisation} =
      Organisations.create_organisation(scope, valid_organisation_attributes(attrs), %{
        ip: "127.0.0.1",
        user_agent: "ExUnit"
      })

    organisation
  end
end
