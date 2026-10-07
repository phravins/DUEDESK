defmodule DueDesk.Billing.PlansTest do
  use ExUnit.Case, async: true

  alias DueDesk.Billing.Plans

  test "plan limits match the Product Definition" do
    free = Plans.get("free")
    assert {free.max_organisations, free.max_members, free.max_due_items} == {1, 2, 10}
    assert free.storage_bytes == 100 * 1024 * 1024

    business = Plans.get("business")

    assert {business.max_organisations, business.max_members, business.max_due_items} ==
             {3, 5, 50}

    assert {business.monthly_inr, business.annual_inr} == {100, 1000}

    ent = Plans.get("entrepreneur")
    assert ent.max_organisations == :unlimited
    assert {ent.max_members, ent.max_super_admins, ent.max_due_items} == {100, 3, 500}
    assert {ent.monthly_inr, ent.annual_inr} == {500, 5000}
  end

  test "unknown plan codes fall back to Free" do
    assert Plans.get("nope").code == "free"
    assert Plans.get(nil).code == "free"
  end

  test "all/0 lists plans from cheapest" do
    assert Enum.map(Plans.all(), & &1.code) == ["free", "business", "entrepreneur"]
  end

  test "format_bytes/1" do
    assert Plans.format_bytes(0) == "0 B"
    assert Plans.format_bytes(100 * 1024 * 1024) == "100 MB"
    assert Plans.format_bytes(2 * 1024 * 1024 * 1024) == "2 GB"
  end
end
