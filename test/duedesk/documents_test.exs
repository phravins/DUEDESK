defmodule DueDesk.DocumentsTest do
  use DueDesk.DataCase, async: true

  import DueDesk.TenancyFixtures
  import DueDesk.DueItemsFixtures
  import DueDesk.DocumentsFixtures

  alias DueDesk.{Documents, DueItems}
  alias DueDesk.Audit.AuditEvent
  alias DueDesk.Billing.Plans
  alias DueDesk.Documents.Document

  setup do
    owner = account_scope_fixture()
    admin = member_scope_fixture(owner, "admin")
    user = member_scope_fixture(owner, "user")
    other_user = member_scope_fixture(owner, "user")
    item = due_item_fixture(admin, recurrence: "annual", primary_user_id: user.user.id)
    %{owner: owner, admin: admin, user: user, other_user: other_user, item: item}
  end

  defp audit(item, action) do
    Repo.all(
      from e in AuditEvent,
        where: e.subject_id == ^item.id and e.action == ^action
    )
  end

  describe "prepare_upload/2" do
    test "measures and stores the file under the account's key", %{user: user} do
      contents = "%PDF-1.4 licence"
      path = tmp_file(contents)

      assert {:ok, upload} =
               Documents.prepare_upload(user, %{path: path, client_name: "Trade licence 2027.pdf"})

      assert upload.filename == "Trade licence 2027.pdf"
      assert upload.byte_size == byte_size(contents)

      assert upload.checksum_sha256 ==
               Base.encode16(:crypto.hash(:sha256, contents), case: :lower)

      assert upload.content_type == "application/pdf"

      assert upload.storage_key ==
               "accounts/#{user.customer_account.id}/documents/#{upload.id}/Trade-licence-2027.pdf"

      assert stored?(upload.storage_key)
    end

    test "cleans the display name and the key name", %{user: user} do
      for {client_name, filename, safe} <- [
            {"../../etc/passwd", "passwd", "passwd"},
            {"C:\\Users\\me\\bill.PDF", "bill.PDF", "bill.PDF"},
            {"  ರಸೀದಿ ಜೂನ್.pdf ", "ರಸೀದಿ ಜೂನ್.pdf", "file.pdf"},
            {"a\u0000b\nc.txt", "abc.txt", "abc.txt"},
            {"..", "file", "file"},
            {"", "file", "file"}
          ] do
        upload = upload_fixture(user, client_name)
        assert upload.filename == filename
        assert String.ends_with?(upload.storage_key, "/#{upload.id}/#{safe}")
      end

      assert Documents.safe_name(String.duplicate("a", 300) <> ".pdf") ==
               String.duplicate("a", 96) <> ".pdf"

      assert Documents.safe_name("weird -- name__.tar.gz") == "weird-name_tar.gz"
    end

    test "refuses empty and oversized files", %{user: user} do
      assert {:error, :empty} =
               Documents.prepare_upload(user, %{path: tmp_file(""), client_name: "a.pdf"})

      big = :binary.copy("x", Documents.max_file_size() + 1)

      assert {:error, :too_large} =
               Documents.prepare_upload(user, %{path: tmp_file(big), client_name: "a.pdf"})
    end

    test "needs a membership" do
      scope = DueDesk.Accounts.Scope.for_user(DueDesk.AccountsFixtures.user_fixture())

      assert {:error, :unauthorized} =
               Documents.prepare_upload(scope, %{path: tmp_file("x"), client_name: "a.pdf"})
    end
  end

  describe "attach_documents/4" do
    test "writes rows on the current cycle, raises the counter and audits each file", ctx do
      %{user: user, item: item} = ctx
      a = upload_fixture(user, "challan.pdf", "%PDF challan")
      b = upload_fixture(user, "receipt.txt", "paid")

      assert {:ok, documents} = Documents.attach_documents(user, item, "supporting", [a, b])
      assert length(documents) == 2

      for doc <- documents do
        assert doc.cycle_id == item.current_cycle_id
        assert doc.due_item_id == item.id
        assert doc.role == "supporting"
        assert doc.uploaded_by_user_id == user.user.id
        assert doc.customer_account_id == user.customer_account.id
      end

      assert storage_used(user) == a.byte_size + b.byte_size

      events = audit(item, "document.uploaded")
      assert length(events) == 2
      event = Enum.find(events, &(&1.metadata["document_id"] == a.id))

      assert event.metadata == %{
               "document_id" => a.id,
               "filename" => "challan.pdf",
               "byte_size" => a.byte_size,
               "role" => "supporting",
               "cycle" => 1
             }

      refute inspect(Enum.map(events, & &1.metadata)) =~ "%PDF challan"

      sentences = Enum.map(DueItems.history(ctx.admin, item), & &1.sentence)

      assert Enum.any?(
               sentences,
               &(&1 =~ "uploaded “challan.pdf” (#{Plans.format_bytes(a.byte_size)})")
             )

      assert [_, _] = Documents.list_documents(user, item)
    end

    test "only current and supporting go on the detail page", %{user: user, item: item} do
      upload = upload_fixture(user)

      assert {:error, :invalid_role} =
               Documents.attach_documents(user, item, "completion", [upload])

      refute stored?(upload.storage_key)
    end

    test "someone who may not act on the DueItem cannot upload", ctx do
      upload = upload_fixture(ctx.other_user)

      assert {:error, :unauthorized} =
               Documents.attach_documents(ctx.other_user, ctx.item, "current", [upload])

      refute stored?(upload.storage_key)

      {:ok, archived} = DueItems.archive_due_item(ctx.admin, ctx.item)
      upload = upload_fixture(ctx.admin)

      assert {:error, :unauthorized} =
               Documents.attach_documents(ctx.admin, archived, "current", [upload])

      assert Repo.aggregate(Document, :count) == 0
      assert storage_used(ctx.admin) == 0
    end

    test "a renewed DueItem is stale", %{user: user, item: item} do
      {:ok, _} = DueItems.renew_due_item(user, item, %{})
      upload = upload_fixture(user)

      assert {:error, :stale} = Documents.attach_documents(user, item, "current", [upload])
      refute stored?(upload.storage_key)
    end

    test "storage is checked against the account row, not the scope", ctx do
      %{user: user, item: item} = ctx
      limit = Plans.get("free").storage_bytes
      upload = upload_fixture(user, "a.pdf", "12345")

      # The scope still says 0 bytes used.
      put_storage_used(user, limit - 4)

      assert {:error, {:limit_reached, %{resource: :storage, limit: ^limit, used: used}}} =
               Documents.attach_documents(user, item, "current", [upload])

      assert used == limit - 4
      refute stored?(upload.storage_key)
      assert storage_used(user) == limit - 4

      # Exactly at the limit is fine; nothing existing is ever removed.
      put_storage_used(user, limit - 5)
      upload = upload_fixture(user, "a.pdf", "12345")
      assert {:ok, [_]} = Documents.attach_documents(user, item, "current", [upload])
      assert storage_used(user) == limit
    end
  end

  describe "get_document/2" do
    test "follows the DueItem's access", ctx do
      doc = document_fixture(ctx.user, ctx.item)

      assert {:ok, %Document{due_item: %{id: item_id}}} = Documents.get_document(ctx.user, doc.id)
      assert item_id == ctx.item.id
      assert {:ok, _} = Documents.get_document(ctx.admin, doc.id)
      assert {:error, :not_found} = Documents.get_document(ctx.other_user, doc.id)
      assert {:error, :not_found} = Documents.get_document(account_scope_fixture(), doc.id)
      assert {:error, :not_found} = Documents.get_document(ctx.admin, Ecto.UUID.generate())
      assert {:error, :not_found} = Documents.get_document(ctx.admin, "nope")
      assert Documents.list_documents(ctx.other_user, ctx.item) == []
    end
  end

  describe "delete_document/2" do
    test "the uploader removes it while the cycle is open", ctx do
      doc = document_fixture(ctx.user, ctx.item, contents: "abcdef")
      assert storage_used(ctx.user) == 6

      assert {:error, :not_found} = Documents.delete_document(ctx.other_user, doc)
      assert {:ok, _} = Documents.delete_document(ctx.user, doc)

      assert Repo.get(Document, doc.id) == nil
      refute stored?(doc.storage_key)
      assert storage_used(ctx.user) == 0

      assert [event] = audit(ctx.item, "document.deleted")
      assert event.metadata["filename"] == "receipt.pdf"

      assert Enum.any?(
               DueItems.history(ctx.admin, ctx.item),
               &(&1.sentence =~ "removed “receipt.pdf”")
             )

      assert {:error, :not_found} = Documents.delete_document(ctx.user, doc)
    end

    test "after renewal only an Administrator can remove it", ctx do
      doc = document_fixture(ctx.user, ctx.item)
      {:ok, _} = DueItems.renew_due_item(ctx.user, ctx.item, %{})

      assert {:error, :unauthorized} = Documents.delete_document(ctx.user, doc)
      assert stored?(doc.storage_key)
      assert {:ok, _} = Documents.delete_document(ctx.admin, doc)
      refute stored?(doc.storage_key)
    end

    test "a User cannot remove an Administrator's upload", ctx do
      doc = document_fixture(ctx.admin, ctx.item)
      assert {:error, :unauthorized} = Documents.delete_document(ctx.user, doc)
      assert stored?(doc.storage_key)
    end

    test "another account cannot remove it", ctx do
      doc = document_fixture(ctx.user, ctx.item)
      assert {:error, :not_found} = Documents.delete_document(account_scope_fixture(), doc)
      assert stored?(doc.storage_key)
    end
  end

  describe "reconcile_storage/1" do
    @tag :capture_log
    test "corrects a drifted counter", ctx do
      document_fixture(ctx.user, ctx.item, contents: "1234")
      put_storage_used(ctx.user, 999)

      account_id = ctx.user.customer_account.id
      assert {:ok, %{before: 999, after: 4}} = Documents.reconcile_storage(account_id)
      assert storage_used(ctx.user) == 4
      assert {:ok, %{before: 4, after: 4}} = Documents.reconcile_storage(account_id)
    end
  end
end
