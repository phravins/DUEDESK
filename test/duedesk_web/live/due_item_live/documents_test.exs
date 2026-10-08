defmodule DueDeskWeb.DueItemLive.DocumentsTest do
  use DueDeskWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest
  import DueDesk.TenancyFixtures
  import DueDesk.DueItemsFixtures
  import DueDesk.DocumentsFixtures

  alias DueDesk.{Documents, DueItems, Repo}
  alias DueDesk.Billing.Plans
  alias DueDesk.Documents.Document

  defp file(name, content \\ "%PDF-1.4 test"),
    do: %{name: name, content: content, type: MIME.from_path(name)}

  defp attach(lv, form, files) do
    input = file_input(lv, form, :documents, files)
    for %{name: name} <- files, do: render_upload(input, name)
    input
  end

  defp documents(item), do: Repo.all(from d in Document, where: d.due_item_id == ^item.id)

  describe "detail page as User" do
    setup :register_and_log_in_account_user

    setup %{scope: scope} do
      admin = member_scope_fixture(scope, "admin")

      item =
        due_item_fixture(admin,
          title: "Fire safety NOC",
          recurrence: "annual",
          primary_user_id: scope.user.id
        )

      %{admin: admin, item: item}
    end

    test "uploads current and supporting documents", %{conn: conn, scope: scope, item: item} do
      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}")
      assert has_element?(lv, "#documents-current", "No current document yet.")

      lv |> element("#upload-documents") |> render_click()
      assert has_element?(lv, "#storage-used", "0 B of 100 MB")

      attach(lv, "#upload-form", [file("NOC 2027.pdf"), file("Inspection.jpg", "jpeg")])
      assert has_element?(lv, "#document-selection", "NOC 2027.pdf")

      lv |> form("#upload-form", %{"upload" => %{"role" => "current"}}) |> render_submit()

      assert has_element?(lv, "#flash-info", "2 documents uploaded.")
      refute has_element?(lv, "#upload-form")
      assert has_element?(lv, "#documents-current", "NOC 2027.pdf")
      assert has_element?(lv, "#documents-current", "Inspection.jpg")
      assert has_element?(lv, "#history", "uploaded “NOC 2027.pdf”")

      lv |> element("#upload-documents") |> render_click()
      attach(lv, "#upload-form", [file("Refill receipt.txt", "paid")])
      lv |> form("#upload-form", %{"upload" => %{"role" => "supporting"}}) |> render_submit()

      assert has_element?(lv, "#flash-info", "Document uploaded.")
      assert has_element?(lv, "#documents-supporting", "Refill receipt.txt")

      [doc | _] = Documents.list_documents(scope, item)
      assert has_element?(lv, "#download-#{doc.id}[href='/documents/#{doc.id}/download']")
      assert storage_used(scope) == byte_size("%PDF-1.4 test") + 4 + 4
    end

    test "rejects a file that is too large", %{conn: conn, item: item} do
      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}")
      lv |> element("#upload-documents") |> render_click()

      big = :binary.copy("x", Documents.max_file_size() + 1)
      input = file_input(lv, "#upload-form", :documents, [file("scan.pdf", big)])
      assert {:error, [[_ref, :too_large]]} = render_upload(input, "scan.pdf")

      assert has_element?(
               lv,
               "#document-selection",
               "This file is larger than #{Plans.format_bytes(Documents.max_file_size())}."
             )

      assert has_element?(lv, "#save-upload[disabled]")
      assert documents(item) == []
    end

    test "at the storage limit shows the notice instead of the upload", %{
      conn: conn,
      scope: scope,
      item: item
    } do
      put_storage_used(scope, Plans.get("free").storage_bytes)
      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}")
      lv |> element("#upload-documents") |> render_click()

      assert has_element?(lv, "#storage-full", "storage limit of 100 MB")
      refute has_element?(lv, "#upload-form")
    end

    test "removes their own upload only while the cycle is open", %{
      conn: conn,
      scope: scope,
      admin: admin,
      item: item
    } do
      mine = document_fixture(scope, item, filename: "mine.pdf")
      theirs = document_fixture(admin, item, filename: "theirs.pdf")

      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}")
      assert has_element?(lv, "#remove-document-#{mine.id}")
      refute has_element?(lv, "#remove-document-#{theirs.id}")

      lv |> element("#remove-document-#{mine.id}") |> render_click()
      assert has_element?(lv, "#flash-info", "Removed “mine.pdf”.")
      refute has_element?(lv, "#document-#{mine.id}")
      refute stored?(mine.storage_key)

      # Removing someone else's document directly does nothing.
      render_click(lv, "remove_document", %{"id" => theirs.id})
      assert has_element?(lv, "#flash-error", "This document can no longer be removed.")
      assert stored?(theirs.storage_key)

      kept = document_fixture(scope, item, filename: "kept.pdf")
      {:ok, _} = DueItems.renew_due_item(scope, item, %{})

      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}")
      assert has_element?(lv, "#cycle-documents-#{item.current_cycle_id}", "kept.pdf")
      refute has_element?(lv, "#remove-document-#{kept.id}")
    end
  end

  describe "detail page as Super Admin" do
    setup :register_and_log_in_super_admin

    test "an archived DueItem's documents can be downloaded but not added", %{
      conn: conn,
      scope: scope
    } do
      item = due_item_fixture(scope)
      doc = document_fixture(scope, item, filename: "contract.pdf")
      {:ok, _} = DueItems.archive_due_item(scope, item)

      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}")
      assert has_element?(lv, "#download-#{doc.id}")
      refute has_element?(lv, "#upload-documents")

      render_click(lv, "open_panel", %{"panel" => "upload"})
      refute has_element?(lv, "#upload-form")

      # Administrators may still remove documents of a closed DueItem.
      assert has_element?(lv, "#remove-document-#{doc.id}")
    end
  end

  describe "Journey 2 with a document" do
    setup :register_and_log_in_account_user

    test "the renewal's document is Current on the next cycle; the old one moves to Previous cycles",
         %{conn: conn, scope: scope} do
      admin = member_scope_fixture(scope, "admin")

      item =
        due_item_fixture(admin,
          title: "Trade licence",
          recurrence: "annual",
          primary_user_id: scope.user.id
        )

      old = document_fixture(scope, item, filename: "licence-2026.pdf")

      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}/renew")
      assert has_element?(lv, "#current-cycle-documents", "licence-2026.pdf")

      attach(lv, "#renew-form", [file("licence-2027.pdf")])

      {:ok, show, _html} =
        lv
        |> form("#renew-form", %{"completion" => %{"note" => "Renewed at the ward office"}})
        |> render_submit()
        |> follow_redirect(conn, ~p"/due-items/#{item}")

      assert has_element?(show, "#flash-info", "The next cycle has been created.")
      assert has_element?(show, "#documents-current", "licence-2027.pdf")
      refute has_element?(show, "#documents-current", "licence-2026.pdf")
      assert has_element?(show, "#cycle-documents-#{item.current_cycle_id}", "licence-2026.pdf")
      assert stored?(old.storage_key)

      renewed = reload(admin, item)

      assert [%Document{role: "current"}] =
               Enum.filter(documents(item), &(&1.cycle_id == renewed.current_cycle_id))
    end

    test "a validation error keeps the selection and stores nothing", %{conn: conn, scope: scope} do
      admin = member_scope_fixture(scope, "admin")

      item =
        due_item_fixture(admin,
          recurrence: "custom",
          recurrence_unit: "explicit",
          due_date: days_from_today(scope, 10),
          primary_user_id: scope.user.id
        )

      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}/renew")
      attach(lv, "#renew-form", [file("ack.pdf")])

      lv
      |> form("#renew-form", %{
        "completion" => %{"next_due_date" => days_from_today(scope, 1)}
      })
      |> render_submit()

      assert has_element?(lv, "#document-selection", "ack.pdf")
      assert documents(item) == []
      assert storage_used(scope) == 0
    end
  end

  describe "Journey 4 with a document" do
    setup :register_and_log_in_account_user

    test "the Administrator sees the completion document in the awaiting banner", %{
      conn: conn,
      scope: scope
    } do
      admin = member_scope_fixture(scope, "admin")

      item =
        due_item_fixture(admin,
          title: "Pest control contract",
          primary_user_id: scope.user.id
        )

      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}/complete")
      assert has_element?(lv, "#completion-documents")
      attach(lv, "#complete-form", [file("signed-contract.pdf")])

      {:ok, _list, _html} =
        lv
        |> form("#complete-form", %{"completion" => %{"note" => "Contract signed"}})
        |> render_submit()
        |> follow_redirect(conn, ~p"/due-items")

      assert [%Document{role: "completion", cycle_id: cycle_id}] = documents(item)
      assert cycle_id == item.current_cycle_id

      {:ok, detail, _html} = live(log_in_user(build_conn(), admin.user), ~p"/due-items/#{item}")
      assert has_element?(detail, "#awaiting-banner #awaiting-documents", "signed-contract.pdf")
    end

    test "files that do not fit in storage are not saved", %{conn: conn, scope: scope} do
      admin = member_scope_fixture(scope, "admin")
      item = due_item_fixture(admin, primary_user_id: scope.user.id)
      put_storage_used(scope, Plans.get("free").storage_bytes - 3)

      {:ok, lv, _html} = live(conn, ~p"/due-items/#{item}/complete")
      attach(lv, "#complete-form", [file("big.pdf", "123456")])
      lv |> form("#complete-form") |> render_submit()

      assert has_element?(lv, "#document-error", "Not enough storage left")
      assert reload(admin, item).disposition_state == nil
      assert documents(item) == []
    end
  end
end
