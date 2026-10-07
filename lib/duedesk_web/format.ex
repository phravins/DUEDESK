defmodule DueDeskWeb.Format do
  @moduledoc """
  Display formatting shared by every screen (UX spec §76).
  """

  @doc """
  Formats a date as `15 Mar 2027`. Returns an em dash for nil.

      iex> DueDeskWeb.Format.date(~D[2027-03-15])
      "15 Mar 2027"
  """
  def date(nil), do: "—"
  def date(%Date{} = date), do: Calendar.strftime(date, "%d %b %Y")
  def date(%DateTime{} = dt), do: dt |> DateTime.to_date() |> date()

  @doc """
  Formats a UTC timestamp in the account timezone as `15 Mar 2027, 4:05 PM`.
  """
  def datetime(nil, _tz), do: "—"

  def datetime(%DateTime{} = dt, tz) do
    dt |> DateTime.shift_zone!(tz) |> Calendar.strftime("%d %b %Y, %-I:%M %p")
  end

  @doc """
  Formats a stored mobile number (`+919876543210`) as `+91 98765 43210`.
  """
  def mobile(nil), do: "—"

  def mobile("+91" <> <<a::binary-size(5), b::binary-size(5)>>), do: "+91 #{a} #{b}"
  def mobile(other), do: other

  @doc "Formats rupees: `₹1,000`."
  def inr(amount) when is_integer(amount) do
    "₹" <> group_indian(Integer.to_string(amount))
  end

  # Indian digit grouping: 1,00,000
  defp group_indian(digits) when byte_size(digits) <= 3, do: digits

  defp group_indian(digits) do
    {head, last3} = String.split_at(digits, -3)

    head =
      head
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(2)
      |> Enum.map_join(",", &Enum.join/1)
      |> String.reverse()

    head <> "," <> last3
  end
end
