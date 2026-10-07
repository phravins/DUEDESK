defmodule DueDeskWeb.PageControllerTest do
  use DueDeskWeb.ConnCase, async: true

  test "GET / shows the public home page", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ "Know what is due before it becomes overdue."
    assert html =~ ~p"/users/register"
    assert html =~ ~p"/pricing"
  end

  test "GET /pricing lists the three plans with Indian pricing", %{conn: conn} do
    html = conn |> get(~p"/pricing") |> html_response(200)

    for plan <- ["Free", "Business", "Entrepreneur"], do: assert(html =~ plan)
    assert html =~ "₹100"
    assert html =~ "₹1,000"
    assert html =~ "₹5,000"
    assert html =~ "Core DueDesk functionality included"
  end
end
