defmodule DueDeskWeb.FormatTest do
  use ExUnit.Case, async: true

  import DueDeskWeb.Format
  doctest DueDeskWeb.Format

  test "date/1" do
    assert date(~D[2027-03-05]) == "05 Mar 2027"
    assert date(~U[2027-03-05 10:00:00Z]) == "05 Mar 2027"
    assert date(nil) == "—"
  end

  test "datetime/2 shows the account timezone" do
    assert datetime(~U[2027-03-15 10:35:00Z], "Asia/Kolkata") == "15 Mar 2027, 4:05 PM"
    assert datetime(nil, "Asia/Kolkata") == "—"
  end

  test "mobile/1" do
    assert mobile("+919876543210") == "+91 98765 43210"
    assert mobile(nil) == "—"
  end

  test "inr/1 uses Indian digit grouping" do
    assert inr(0) == "₹0"
    assert inr(100) == "₹100"
    assert inr(1_000) == "₹1,000"
    assert inr(100_000) == "₹1,00,000"
    assert inr(12_345_678) == "₹1,23,45,678"
  end
end
