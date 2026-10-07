defmodule DueDesk.Billing.Plans do
  @moduledoc """
  DueDesk plan tiers. Plans differ by capacity only; every plan gets the
  same core product (Product Definition §13).

  Never compare plan codes in feature code — use the `DueDesk.Billing`
  `can_*?` functions, which read these limits.
  """

  @mb 1024 * 1024
  @gb 1024 * @mb

  @plans [
    %{
      code: "free",
      name: "Free",
      monthly_inr: 0,
      annual_inr: 0,
      max_organisations: 1,
      max_members: 2,
      max_super_admins: 1,
      max_due_items: 10,
      storage_bytes: 100 * @mb
    },
    %{
      code: "business",
      name: "Business",
      monthly_inr: 100,
      annual_inr: 1_000,
      max_organisations: 3,
      max_members: 5,
      max_super_admins: 1,
      max_due_items: 50,
      storage_bytes: 2 * @gb
    },
    %{
      code: "entrepreneur",
      name: "Entrepreneur",
      monthly_inr: 500,
      annual_inr: 5_000,
      max_organisations: :unlimited,
      max_members: 100,
      max_super_admins: 3,
      max_due_items: 500,
      storage_bytes: 10 * @gb
    }
  ]

  @doc "All plans in display order."
  def all, do: @plans

  @doc "Gets a plan by code. Unknown codes fall back to Free."
  def get(code) do
    Enum.find(@plans, &(&1.code == code)) || hd(@plans)
  end

  @doc "Formats a byte size the way plan limits are written (100 MB, 2 GB)."
  def format_bytes(bytes) when bytes >= @gb do
    value = bytes / @gb
    if value == trunc(value), do: "#{trunc(value)} GB", else: "#{Float.round(value, 1)} GB"
  end

  def format_bytes(bytes) when bytes >= @mb do
    value = bytes / @mb
    if value == trunc(value), do: "#{trunc(value)} MB", else: "#{Float.round(value, 1)} MB"
  end

  def format_bytes(bytes) when bytes >= 1024, do: "#{div(bytes, 1024)} KB"
  def format_bytes(bytes), do: "#{bytes} B"
end
