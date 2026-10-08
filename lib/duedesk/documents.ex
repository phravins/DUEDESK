defmodule DueDesk.Documents do
  @moduledoc """
  Documents on DueItems (Product Definition §10): any file type, up to
  30 MB each, kept on a cycle and never overwritten. They follow the
  DueItem's access rules; there are no separate document permissions.

  Uploading has two steps:

    1. `prepare_upload/2` measures the file on the server (size,
       SHA-256), stores it and returns the upload's attributes;
    2. the rows are written inside the transaction that needs them
       (`attach_documents/4`, or renewing and completing through
       `multi_attach/6`), which checks storage against the locked account
       row and writes an audit event per file.

  If that transaction fails, the stored files are removed again, so no
  file is left without a row. Plan storage only ever blocks uploads;
  nothing is deleted automatically. File contents never go into audit
  events or logs.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Ecto.Multi
  alias DueDesk.{Audit, Billing, DueItems, Permissions, Repo}
  alias DueDesk.Accounts.Scope
  alias DueDesk.Documents.{Document, Storage}
  alias DueDesk.DueItems.DueItem
  alias DueDesk.Tenancy.CustomerAccount

  @type upload :: %{
          id: Ecto.UUID.t(),
          filename: String.t(),
          storage_key: String.t(),
          content_type: String.t(),
          byte_size: pos_integer(),
          checksum_sha256: String.t()
        }

  @max_files 5

  @doc "The largest file accepted, in bytes (30 MB)."
  def max_file_size, do: Application.get_env(:duedesk, :document_max_file_size, 30 * 1024 * 1024)

  @doc "How many files can be uploaded at once."
  def max_files, do: @max_files

  ## Uploading

  @doc """
  Measures and stores an uploaded file. `path` is the temporary file and
  `client_name` the name the browser sent, used only as a display name.

  Returns `{:ok, upload}` or `{:error, :empty | :too_large |
  :storage_failed | :unauthorized}`.
  """
  @spec prepare_upload(Scope.t(), %{path: Path.t(), client_name: String.t()}) ::
          {:ok, upload()} | {:error, atom()}
  def prepare_upload(%Scope{} = scope, %{path: path, client_name: client_name}) do
    %{size: size} = File.stat!(path)

    cond do
      not Permissions.member?(scope) ->
        {:error, :unauthorized}

      size == 0 ->
        {:error, :empty}

      size > max_file_size() ->
        {:error, :too_large}

      true ->
        id = Ecto.UUID.generate()
        filename = clean_filename(client_name)
        key = "accounts/#{Scope.account_id!(scope)}/documents/#{id}/#{safe_name(filename)}"
        content_type = MIME.from_path(filename)

        case Storage.put(key, path, content_type) do
          :ok ->
            {:ok,
             %{
               id: id,
               filename: filename,
               storage_key: key,
               content_type: content_type,
               byte_size: size,
               checksum_sha256: sha256(path)
             }}

          {:error, reason} ->
            Logger.error("Could not store document #{id}: #{reason_label(reason)}")
            {:error, :storage_failed}
        end
    end
  end

  @doc "Removes stored files whose rows were never written."
  def discard_uploads(uploads) do
    uploads |> Enum.map(& &1.storage_key) |> remove_objects()
  end

  @doc """
  Passes `result` through, removing the stored `uploads` when it is not
  `{:ok, _}`.
  """
  def discard_on_error({:ok, _} = result, _uploads), do: result

  def discard_on_error(result, uploads) do
    discard_uploads(uploads)
    result
  end

  @doc """
  The display name for a file: its base name without control characters,
  at most 255 characters, or `file`.
  """
  def clean_filename(name) when is_binary(name) do
    name
    |> String.replace("\\", "/")
    |> Path.basename()
    |> String.replace(~r/[\x00-\x1F\x7F]/u, "")
    |> String.trim()
    |> String.slice(0, 255)
    |> case do
      "" -> "file"
      "." -> "file"
      ".." -> "file"
      clean -> clean
    end
  end

  def clean_filename(_name), do: "file"

  @doc """
  The name used in a storage key: only `A-Z a-z 0-9 . _ -`, at most 100
  characters, keeping a simple extension.
  """
  def safe_name(filename) do
    ext = Path.extname(filename)
    ext = if Regex.match?(~r/^\.[A-Za-z0-9]{1,15}$/, ext), do: ext, else: ""

    base =
      filename
      |> String.slice(0, String.length(filename) - String.length(ext))
      |> String.replace(~r/[^A-Za-z0-9._-]+/, "-")
      |> String.replace(~r/([-._])[-._]+/, "\\1")
      |> String.trim("-")
      |> String.trim(".")
      |> String.slice(0, 100 - String.length(ext))

    if base == "", do: "file" <> ext, else: base <> ext
  end

  defp sha256(path) do
    path
    |> File.stream!(64 * 1024)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  ## Attaching

  @doc """
  Adds the steps that write `uploads` as documents to `multi`: lock the
  account row, check storage against it, insert the rows, raise the
  storage counter and audit each file on the DueItem.

  `cycle_fun` receives the multi's changes and returns the cycle the
  documents go on. Does nothing when `uploads` is empty. Fails with
  `{:error, :storage_lock, {:limit_reached, info}, _}` when the files do
  not fit.
  """
  def multi_attach(multi, scope, item, cycle_fun, role, uploads)

  def multi_attach(%Multi{} = multi, _scope, _item, _cycle_fun, _role, []), do: multi

  def multi_attach(
        %Multi{} = multi,
        %Scope{} = scope,
        %DueItem{} = item,
        cycle_fun,
        role,
        uploads
      )
      when role in ["current", "supporting", "completion"] do
    account_id = Scope.account_id!(scope)
    total = uploads |> Enum.map(& &1.byte_size) |> Enum.sum()

    multi
    |> Multi.run(:storage_lock, fn repo, _ ->
      from(a in CustomerAccount,
        where: a.id == ^account_id,
        lock: "FOR UPDATE",
        select: a.storage_used_bytes
      )
      |> repo.one()
      |> case do
        nil ->
          {:error, :not_found}

        used ->
          with :ok <- Billing.check_storage(scope, used, total), do: {:ok, used}
      end
    end)
    |> Multi.run(:documents, fn repo, changes ->
      cycle = cycle_fun.(changes)
      now = DateTime.utc_now(:second)

      rows =
        for upload <- uploads do
          upload
          |> Map.take([:id, :filename, :storage_key, :content_type, :byte_size, :checksum_sha256])
          |> Map.merge(%{
            customer_account_id: account_id,
            due_item_id: item.id,
            cycle_id: cycle.id,
            uploaded_by_user_id: scope.user.id,
            role: role,
            inserted_at: now,
            updated_at: now
          })
        end

      {_count, documents} = repo.insert_all(Document, rows, returning: true)
      {:ok, %{cycle: cycle, documents: documents}}
    end)
    |> Multi.update_all(
      :storage_used,
      from(a in CustomerAccount, where: a.id == ^account_id),
      inc: [storage_used_bytes: total]
    )
    |> then(fn multi ->
      Enum.reduce(uploads, multi, fn upload, multi ->
        Audit.multi_log(multi, {:document_audit, upload.id}, scope, "document.uploaded", item,
          metadata: fn %{documents: %{cycle: cycle}} ->
            %{
              "document_id" => upload.id,
              "filename" => upload.filename,
              "byte_size" => upload.byte_size,
              "role" => role,
              "cycle" => cycle.sequence
            }
          end
        )
      end)
    end)
  end

  @doc """
  Attaches `uploads` to the current cycle of an active DueItem, as
  `current` or `supporting` documents. Anyone who may act on the DueItem
  may upload. The stored files are removed again on any error.

  Returns `{:ok, documents}`, `{:error, {:limit_reached, info}}`,
  `{:error, :stale}`, `{:error, :invalid_role}` or
  `{:error, :unauthorized}`.
  """
  def attach_documents(%Scope{} = scope, %DueItem{} = item, role, uploads) do
    scope
    |> do_attach(item, role, uploads)
    |> discard_on_error(uploads)
  end

  defp do_attach(_scope, _item, role, _uploads) when role not in ["current", "supporting"],
    do: {:error, :invalid_role}

  defp do_attach(_scope, _item, _role, []), do: {:ok, []}

  defp do_attach(scope, item, role, uploads) do
    with {:ok, fresh} <- visible(scope, item.id),
         true <- Permissions.can_upload_document?(scope, fresh) || {:error, :unauthorized},
         true <- fresh.current_cycle_id == item.current_cycle_id || {:error, :stale} do
      account_id = Scope.account_id!(scope)

      Multi.new()
      |> Multi.run(:open_cycle, fn repo, _ ->
        locked =
          repo.one(
            from(i in DueItem,
              where:
                i.id == ^fresh.id and i.customer_account_id == ^account_id and
                  i.status == "active" and is_nil(i.disposition_state),
              lock: "FOR UPDATE"
            )
          )

        if locked && locked.current_cycle_id == fresh.current_cycle_id,
          do: {:ok, fresh.current_cycle},
          else: {:error, :stale}
      end)
      |> multi_attach(scope, fresh, & &1.open_cycle, role, uploads)
      |> Repo.transaction()
      |> case do
        {:ok, %{documents: %{documents: documents}}} -> {:ok, documents}
        {:error, :open_cycle, :stale, _} -> {:error, :stale}
        {:error, :storage_lock, :not_found, _} -> {:error, :unauthorized}
        {:error, :storage_lock, reason, _} -> {:error, reason}
      end
    end
  end

  ## Reading

  @doc """
  The documents of a DueItem the scope may see, oldest first, with their
  uploader and cycle. Group them by `cycle_id` for display.
  """
  def list_documents(%Scope{} = scope, %DueItem{} = item) do
    case visible(scope, item.id) do
      {:ok, item} ->
        from(d in Document,
          where: d.due_item_id == ^item.id and d.customer_account_id == ^item.customer_account_id,
          order_by: [asc: d.inserted_at, asc: d.filename],
          preload: [:uploaded_by_user, :cycle]
        )
        |> Repo.all()

      _ ->
        []
    end
  end

  @doc """
  Gets a document whose DueItem the scope may see, with its cycle and
  DueItem. Anything else, including another account's document, is
  `{:error, :not_found}`.
  """
  def get_document(%Scope{} = scope, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Document{} = document <-
           Repo.one(
             from(d in Document,
               where: d.id == ^id and d.customer_account_id == ^Scope.account_id!(scope),
               preload: [:cycle, :uploaded_by_user]
             )
           ),
         {:ok, item} <- DueItems.get_due_item(scope, document.due_item_id) do
      {:ok, %{document | due_item: item}}
    else
      _ -> {:error, :not_found}
    end
  end

  defp visible(scope, id) do
    case DueItems.get_due_item(scope, id) do
      {:ok, item} -> {:ok, item}
      {:error, :not_found} -> {:error, :unauthorized}
    end
  end

  ## Removing

  @doc """
  Removes a document: its row in one transaction with the storage
  counter and an audit event, then the stored file. Administrators and
  Super Admins may remove any document they can see; the person who
  uploaded one may remove it while its cycle is open.

  Returns `{:ok, document}`, `{:error, :not_found}` or
  `{:error, :unauthorized}`.
  """
  def delete_document(%Scope{} = scope, %Document{id: id}) do
    with {:ok, document} <- get_document(scope, id),
         true <-
           Permissions.can_delete_document?(scope, document.due_item, document) ||
             {:error, :unauthorized} do
      Multi.new()
      |> Multi.delete(:document, document, stale_error_field: :id)
      |> release_storage(Scope.account_id!(scope), document.byte_size)
      |> Audit.multi_log(:audit, scope, "document.deleted", document.due_item,
        metadata: %{
          "document_id" => document.id,
          "filename" => document.filename,
          "byte_size" => document.byte_size
        }
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{document: deleted}} ->
          remove_objects([deleted.storage_key])
          {:ok, deleted}

        {:error, :document, _changeset, _} ->
          {:error, :not_found}
      end
    end
  end

  @doc """
  Adds the steps that release a DueItem's documents before it is
  permanently deleted: their sizes come off the storage counter and the
  multi's `:released_documents` holds `%{keys: keys, count: n, bytes: b}`.
  The rows go with the DueItem; remove the files with `remove_objects/1`
  after the transaction commits.
  """
  def multi_release(%Multi{} = multi, %DueItem{} = item) do
    Multi.run(multi, :released_documents, fn repo, _ ->
      rows =
        repo.all(
          from(d in Document,
            where:
              d.due_item_id == ^item.id and d.customer_account_id == ^item.customer_account_id,
            select: {d.storage_key, d.byte_size}
          )
        )

      bytes = rows |> Enum.map(&elem(&1, 1)) |> Enum.sum()

      if bytes > 0 do
        {1, _} =
          repo.update_all(release_query(item.customer_account_id, bytes), [])
      end

      {:ok, %{keys: Enum.map(rows, &elem(&1, 0)), count: length(rows), bytes: bytes}}
    end)
  end

  defp release_storage(multi, account_id, bytes) do
    Multi.update_all(multi, :storage_used, release_query(account_id, bytes), [])
  end

  defp release_query(account_id, bytes) do
    from(a in CustomerAccount,
      where: a.id == ^account_id,
      update: [
        set: [storage_used_bytes: fragment("GREATEST(? - ?, 0)", a.storage_used_bytes, ^bytes)]
      ]
    )
  end

  @doc """
  Removes stored files. A failure is logged with the key's document id
  only; `reconcile_storage/1` keeps the counter right regardless.
  """
  def remove_objects(keys) do
    Enum.each(keys, fn key ->
      case Storage.delete(key) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error(
            "Could not remove stored document #{document_id(key)}: #{reason_label(reason)}"
          )
      end
    end)
  end

  defp document_id(key) do
    case String.split(key, "/") do
      ["accounts", _account, "documents", id | _] -> id
      _ -> "(unknown)"
    end
  end

  defp reason_label({:http_status, status}), do: "HTTP #{status}"
  defp reason_label(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_label(%{__struct__: module}), do: inspect(module)
  defp reason_label(_reason), do: "error"

  ## Storage counter

  @doc """
  Recomputes an account's `storage_used_bytes` from its documents and
  corrects the counter if it drifted. Logs only the account id and the
  difference.

  Returns `{:ok, %{before: bytes, after: bytes}}`.
  """
  def reconcile_storage(account_id) do
    Repo.transaction(fn ->
      used =
        Repo.one!(
          from(a in CustomerAccount,
            where: a.id == ^account_id,
            lock: "FOR UPDATE",
            select: a.storage_used_bytes
          )
        )

      actual =
        Repo.one(
          from(d in Document,
            where: d.customer_account_id == ^account_id,
            select: coalesce(sum(d.byte_size), 0)
          )
        )
        |> to_integer()

      if actual != used do
        Repo.update_all(from(a in CustomerAccount, where: a.id == ^account_id),
          set: [storage_used_bytes: actual]
        )

        Logger.warning("Corrected storage for account #{account_id} by #{actual - used} bytes")
      end

      %{before: used, after: actual}
    end)
  end

  defp to_integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp to_integer(value), do: value
end
