defmodule DueDeskWeb.PageController do
  use DueDeskWeb, :controller

  def home(conn, _params) do
    render(conn, :home, page_title: "Know what is due before it becomes overdue")
  end

  def pricing(conn, _params) do
    render(conn, :pricing, page_title: "Pricing", plans: DueDesk.Billing.Plans.all())
  end
end
