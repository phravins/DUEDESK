defmodule DueDesk.Organisations.Identifier do
  @moduledoc """
  Registration identifiers for Organisations (Product Definition §6).

  The Organisation type decides which identifier is required:

    * Proprietorship and Partnership — Udyam Registration Number
    * LLP — LLPIN
    * Private Limited — CIN

  Identifiers are compared in normalised form (uppercase, without spaces
  or hyphens), so `udyam-mh-01-0001234` and `UDYAM MH 01 0001234` are the
  same Organisation.
  """

  @types [
    {"proprietorship", "Proprietorship", "udyam"},
    {"partnership", "Partnership", "udyam"},
    {"llp", "LLP", "llpin"},
    {"private_limited", "Private Limited", "cin"}
  ]

  @identifier_types %{
    "udyam" => %{
      label: "Udyam Registration Number",
      short: "Udyam",
      example: "UDYAM-MH-01-0001234",
      pattern: ~r/^UDYAM[A-Z]{2}\d{9}$/
    },
    "llpin" => %{
      label: "LLPIN",
      short: "LLPIN",
      example: "AAB-1234",
      pattern: ~r/^[A-Z]{3}\d{4}$/
    },
    "cin" => %{
      label: "CIN",
      short: "CIN",
      example: "U72900KA2015PTC123456",
      pattern: ~r/^[LU]\d{5}[A-Z]{2}\d{4}[A-Z]{3}\d{6}$/
    }
  }

  @gstin ~r/^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/

  @doc "Organisation type codes."
  def types, do: Enum.map(@types, &elem(&1, 0))

  @doc "`{label, code}` pairs for a type select."
  def type_options, do: Enum.map(@types, fn {code, label, _} -> {label, code} end)

  @doc "Human label for an Organisation type."
  def type_label(type) do
    case List.keyfind(@types, type, 0) do
      {_, label, _} -> label
      nil -> nil
    end
  end

  @doc "The identifier type an Organisation type requires, or nil."
  def identifier_type(type) do
    case List.keyfind(@types, type, 0) do
      {_, _, identifier_type} -> identifier_type
      nil -> nil
    end
  end

  @doc "Field label for an identifier type, e.g. \"LLPIN\"."
  def label(identifier_type), do: fetch(identifier_type, :label, "Registration number")

  @doc "Short name for an identifier type, e.g. \"Udyam\"."
  def short_label(identifier_type), do: fetch(identifier_type, :short, "Identifier")

  @doc "An example identifier in display form."
  def example(identifier_type), do: fetch(identifier_type, :example, nil)

  defp fetch(identifier_type, key, default) do
    case Map.fetch(@identifier_types, identifier_type) do
      {:ok, spec} -> Map.fetch!(spec, key)
      :error -> default
    end
  end

  @doc "Uppercases and removes spaces and hyphens."
  def normalize(nil), do: nil

  def normalize(value) when is_binary(value) do
    value |> String.upcase() |> String.replace(~r/[\s\-]/u, "")
  end

  @doc "True when the normalised identifier matches the type's format."
  def valid?(identifier_type, normalized) when is_binary(normalized) do
    case Map.fetch(@identifier_types, identifier_type) do
      {:ok, %{pattern: pattern}} -> Regex.match?(pattern, normalized)
      :error -> false
    end
  end

  def valid?(_identifier_type, _normalized), do: false

  @doc """
  Builds the display form of a valid, normalised identifier:
  `UDYAM-MH-01-0001234`, `AAB-1234` or the 21-character CIN.
  """
  def format("udyam", <<"UDYAM", state::binary-size(2), district::binary-size(2), rest::binary>>),
    do: "UDYAM-#{state}-#{district}-#{rest}"

  def format("llpin", <<letters::binary-size(3), digits::binary>>), do: "#{letters}-#{digits}"
  def format(_identifier_type, normalized), do: normalized

  @doc "True when the normalised GSTIN has the 15-character GSTIN format."
  def valid_gstin?(normalized) when is_binary(normalized), do: Regex.match?(@gstin, normalized)
  def valid_gstin?(_), do: false
end
