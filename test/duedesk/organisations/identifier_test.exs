defmodule DueDesk.Organisations.IdentifierTest do
  use ExUnit.Case, async: true

  alias DueDesk.Organisations.Identifier

  test "each Organisation type requires its identifier" do
    assert Identifier.identifier_type("proprietorship") == "udyam"
    assert Identifier.identifier_type("partnership") == "udyam"
    assert Identifier.identifier_type("llp") == "llpin"
    assert Identifier.identifier_type("private_limited") == "cin"
    assert Identifier.identifier_type("trust") == nil
  end

  test "normalises case, spaces and hyphens to the same key" do
    assert Identifier.normalize(" udyam-mh-01-0001234 ") == "UDYAMMH010001234"
    assert Identifier.normalize("UDYAM MH 01 0001234") == "UDYAMMH010001234"
    assert Identifier.normalize("UDYAMMH010001234") == "UDYAMMH010001234"
    assert Identifier.normalize("aab-1234") == "AAB1234"
  end

  describe "valid?/2" do
    test "Udyam" do
      assert Identifier.valid?("udyam", "UDYAMMH010001234")
      refute Identifier.valid?("udyam", "UDYAMMH01000123")
      refute Identifier.valid?("udyam", "UDYAM1H010001234")
      refute Identifier.valid?("udyam", "AAB1234")
    end

    test "LLPIN" do
      assert Identifier.valid?("llpin", "AAB1234")
      refute Identifier.valid?("llpin", "AB1234")
      refute Identifier.valid?("llpin", "AAB12345")
    end

    test "CIN" do
      assert Identifier.valid?("cin", "U72900KA2015PTC123456")
      assert Identifier.valid?("cin", "L17110MH1973PLC019786")
      refute Identifier.valid?("cin", "X72900KA2015PTC123456")
      refute Identifier.valid?("cin", "U72900KA2015PTC12345")
    end

    test "unknown types and nil are invalid" do
      refute Identifier.valid?(nil, "AAB1234")
      refute Identifier.valid?("llpin", nil)
    end
  end

  test "formats the display form" do
    assert Identifier.format("udyam", "UDYAMMH010001234") == "UDYAM-MH-01-0001234"
    assert Identifier.format("llpin", "AAB1234") == "AAB-1234"
    assert Identifier.format("cin", "U72900KA2015PTC123456") == "U72900KA2015PTC123456"
  end

  test "GSTIN" do
    assert Identifier.valid_gstin?("27AAPFU0939F1ZV")
    refute Identifier.valid_gstin?("27AAPFU0939F1Z")
    refute Identifier.valid_gstin?("27AAPFU0939F0ZV")
    refute Identifier.valid_gstin?(nil)
  end
end
