# Demo data for local development:
#
#     mix run priv/repo/seeds.exs   (also run by mix ecto.setup / ecto.reset)
#
# Creates one operator and three Customer Accounts (Free, Business,
# Entrepreneur) with a Super Admin, an Administrator and a User each, and
# Organisations of every type. The Free account is at its Organisation limit.
# Each account gets DueItems in every status: overdue, due soon, up to date,
# an overridden status, an unassigned item, recurring items, an archived item
# and notes, a User's renewal awaiting review and a completed DueItem
# awaiting an Administrator's decision. Some are assigned to the demo User and some are not, so the
# visibility rule can be seen. The Free account stays within its DueItem limit.
# A few small generated documents are attached (a current and a supporting
# document on the Fire safety NOC, a completion receipt on the renewed
# Professional tax cycle); they are stored under uploads/.
# Passwords are generated on every run and printed once to this console.
# Existing records are left alone, so running it twice is safe.
#
# The Business and Entrepreneur accounts each have a pending invitation,
# and the Entrepreneur account's User has WhatsApp reminders turned on.

if Mix.env() != :dev do
  IO.puts("Seeds create demo logins and only run in the dev environment. Skipping.")
else
  alias DueDesk.{Accounts, Admin, Categories, Documents, DueItems, Organisations, Repo, Tenancy}
  alias DueDesk.Accounts.{Scope, User}
  alias DueDesk.Admin.Operator
  alias DueDesk.Documents.Document
  alias DueDesk.DueItems.{Cycle, DueItem}
  alias DueDesk.Tenancy.{Invitation, Membership}

  import Ecto.Query, only: [from: 2]

  password = fn -> "demo-" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false) end

  ensure_user = fn name, email, mobile ->
    case Accounts.get_user_by_email(email) do
      %User{} = user ->
        {user, "(unchanged)"}

      nil ->
        pw = password.()

        {:ok, user} =
          Accounts.register_user(%{name: name, email: email, mobile_number: mobile, password: pw})

        user = user |> User.confirm_changeset() |> Repo.update!()
        {user, pw}
    end
  end

  logins = []

  op_email = "ops@duedesk.local"

  logins =
    if Repo.get_by(Operator, email: op_email) do
      logins ++ [{"Operator console /admin", op_email, "(unchanged)"}]
    else
      pw = password.() <> "-ops"
      {:ok, _} = Admin.create_operator(%{name: "DueDesk Ops", email: op_email, password: pw})
      logins ++ [{"Operator console /admin", op_email, pw}]
    end

  accounts = [
    {"free", "Sharma Traders", "sharma"},
    {"business", "Verma Industries", "verma"},
    {"entrepreneur", "Iyer Group", "iyer"}
  ]

  organisations = %{
    "sharma" => [
      %{name: "Sharma Traders", type: "proprietorship", identifier: "UDYAM-DL-07-0012345"}
    ],
    "verma" => [
      %{name: "Verma Industries LLP", type: "llp", identifier: "AAB-1234"},
      %{
        name: "Verma Auto Components Pvt Ltd",
        type: "private_limited",
        identifier: "U29100MH2015PTC123456",
        gstin: "27AAPFU0939F1ZV"
      }
    ],
    "iyer" => [
      %{name: "Iyer & Sons", type: "partnership", identifier: "UDYAM-TN-02-0045678"},
      %{name: "Iyer Foods Pvt Ltd", type: "private_limited", identifier: "U15400TN2018PTC234567"},
      %{name: "Iyer Logistics LLP", type: "llp", identifier: "AAC-5678"}
    ]
  }

  # {title, category, due offset, expiry offset, primary, extra attrs}
  # Offsets are days from today; primary is :admin, :user or nil.
  demo_due_items = [
    {"GST return (GSTR-3B)", "GST & Income Tax", -5, nil, :user,
     %{"recurrence" => "monthly", "reference_number" => "GSTR3B-MONTHLY"}},
    {"Trade Licence renewal", "Licences & Permits", 12, 15, :user,
     %{"recurrence" => "annual", "related_party" => "Municipal Corporation"}},
    {"Fire safety NOC", "Licences & Permits", 20, 35, :admin, %{}},
    {"Fire & burglary insurance", "Insurance", 150, 165, :admin,
     %{
       "recurrence" => "annual",
       "reference_number" => "POL-4471-2290",
       "related_party" => "New India Assurance"
     }},
    {"Shop rent agreement", "Property & Rent", nil, 240, nil,
     %{"description" => "Eleven-month agreement. Renegotiate the rent before renewal."}},
    {"PF monthly challan", "Labour Compliance (PF/ESI)", -2, nil, :user,
     %{"recurrence" => "monthly"}},
    {"ISO 9001 surveillance audit", "Certifications", 75, nil, :admin,
     %{"recurrence" => "custom", "recurrence_unit" => "month", "recurrence_interval" => "12"}},
    {"Delivery van insurance (van sold)", "Vehicles", 40, nil, :admin, %{}}
  ]

  seed_due_items = fn owner_scope, admin, member ->
    account_id = Scope.account_id!(owner_scope)

    unless Repo.exists?(from(i in DueItem, where: i.customer_account_id == ^account_id)) do
      today = Tenancy.today(owner_scope)
      iso = fn offset -> offset && Date.to_iso8601(Date.add(today, offset)) end
      organisations = Organisations.list_organisations(owner_scope)
      categories = Categories.list_categories(owner_scope, status: "active")

      category_id = fn name ->
        Enum.find(categories, &(&1.name == name)) || List.last(categories)
      end

      member_scope =
        Scope.put_membership(Scope.for_user(member), Tenancy.get_current_membership(member))

      items =
        for {{title, category, due, expiry, primary, extra}, index} <-
              Enum.with_index(demo_due_items) do
          primary_id =
            case primary do
              :admin -> admin.id
              :user -> member.id
              nil -> nil
            end

          additional = if title == "Trade Licence renewal", do: [admin.id], else: []

          {:ok, item} =
            DueItems.create_due_item(
              owner_scope,
              Map.merge(
                %{
                  "title" => title,
                  "organisation_id" =>
                    Enum.at(organisations, rem(index, length(organisations))).id,
                  "category_id" => category_id.(category).id,
                  "due_date" => iso.(due),
                  "expiry_date" => iso.(expiry),
                  "primary_user_id" => primary_id,
                  "additional_user_ids" => additional
                },
                extra
              )
            )

          {title, item}
        end
        |> Map.new()

      {:ok, item} = DueItems.get_due_item(owner_scope, items["PF monthly challan"].id)

      {:ok, _} =
        DueItems.override_status(
          owner_scope,
          item,
          "up_to_date",
          "Paid on the EPFO portal; challan receipt awaited."
        )

      {:ok, item} =
        DueItems.get_due_item(owner_scope, items["Delivery van insurance (van sold)"].id)

      {:ok, _} = DueItems.archive_due_item(owner_scope, item)

      {:ok, item} = DueItems.get_due_item(member_scope, items["GST return (GSTR-3B)"].id)

      {:ok, _} =
        DueItems.add_note(member_scope, item, %{
          "body" => "Waiting for the purchase register from accounts before filing."
        })

      {:ok, item} = DueItems.get_due_item(owner_scope, items["Trade Licence renewal"].id)

      {:ok, _} =
        DueItems.add_note(owner_scope, item, %{
          "body" => "Renewal form is on the municipal portal. Keep last year's receipt handy."
        })
    end
  end

  # Phase 3 lifecycle examples, each added once by title so re-running the
  # seeds on an existing database adds them: a renewal by the User that
  # waits for an Administrator's review, and a completed one-off DueItem
  # awaiting a decision.
  seed_lifecycle = fn owner_scope, member ->
    account_id = Scope.account_id!(owner_scope)
    today = Tenancy.today(owner_scope)
    organisations = Organisations.list_organisations(owner_scope)
    categories = Categories.list_categories(owner_scope, status: "active")

    member_scope =
      Scope.put_membership(Scope.for_user(member), Tenancy.get_current_membership(member))

    category_id = fn name ->
      (Enum.find(categories, &(&1.name == name)) || List.last(categories)).id
    end

    missing? = fn title ->
      not Repo.exists?(
        from(i in DueItem, where: i.customer_account_id == ^account_id and i.title == ^title)
      )
    end

    create = fn attrs ->
      {:ok, item} =
        DueItems.create_due_item(
          owner_scope,
          Map.merge(
            %{
              "organisation_id" => List.first(organisations).id,
              "primary_user_id" => member.id
            },
            attrs
          )
        )

      {:ok, item} = DueItems.get_due_item(member_scope, item.id)
      item
    end

    if organisations != [] and missing?.("Professional tax (PTEC)") do
      item =
        create.(%{
          "title" => "Professional tax (PTEC)",
          "category_id" => category_id.("GST & Income Tax"),
          "due_date" => Date.to_iso8601(Date.add(today, -340)),
          "recurrence" => "annual"
        })

      {:ok, _} =
        DueItems.renew_due_item(member_scope, item, %{
          "completed_on" => Date.to_iso8601(Date.add(today, -2)),
          "note" => "Paid on the Mahakosh portal."
        })
    end

    if organisations != [] and missing?.("Office pest control contract") do
      item =
        create.(%{
          "title" => "Office pest control contract",
          "category_id" => category_id.("Property & Rent"),
          "due_date" => Date.to_iso8601(Date.add(today, 3))
        })

      {:ok, _} = DueItems.complete_due_item(member_scope, item, %{"completed_on" => today})
    end
  end

  # Phase 4 documents, each added once by filename. The files are small
  # PDFs and text files generated here, so no binaries live in the repo.
  pdf = fn lines ->
    text =
      lines
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {line, i} ->
        "BT /F1 #{if i == 0, do: 18, else: 11} Tf 72 #{770 - i * 24} Td (#{line}) Tj ET"
      end)

    """
    %PDF-1.4
    1 0 obj <</Type /Catalog /Pages 2 0 R>> endobj
    2 0 obj <</Type /Pages /Kids [3 0 R] /Count 1>> endobj
    3 0 obj <</Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources <</Font <</F1 5 0 R>>>>>> endobj
    4 0 obj <</Length #{byte_size(text)}>>
    stream
    #{text}
    endstream
    endobj
    5 0 obj <</Type /Font /Subtype /Type1 /BaseFont /Helvetica>> endobj
    trailer <</Root 1 0 R>>
    %%EOF
    """
  end

  tmp_dir = Path.join(System.tmp_dir!(), "duedesk-seed-documents")
  File.mkdir_p!(tmp_dir)

  prepare = fn scope, filename, content ->
    path = Path.join(tmp_dir, filename)
    File.write!(path, content)
    {:ok, upload} = Documents.prepare_upload(scope, %{path: path, client_name: filename})
    File.rm(path)
    upload
  end

  has_document? = fn item, filename ->
    Repo.exists?(
      from(d in Document, where: d.due_item_id == ^item.id and d.filename == ^filename)
    )
  end

  seed_documents = fn owner_scope ->
    account_id = Scope.account_id!(owner_scope)

    find = fn title ->
      Repo.one(
        from(i in DueItem,
          where: i.customer_account_id == ^account_id and i.title == ^title,
          limit: 1
        )
      )
    end

    with %DueItem{} = noc <- find.("Fire safety NOC"),
         {:ok, noc} <- DueItems.get_due_item(owner_scope, noc.id) do
      for {filename, role, content} <- [
            {"Fire-NOC-certificate.pdf", "current",
             pdf.([
               "Fire Safety No Objection Certificate",
               "Issued by the Fire Department",
               "Demo document generated by DueDesk seeds"
             ])},
            {"Extinguisher-refill-receipt.txt", "supporting",
             "Fire extinguisher refill receipt\nSix ABC extinguishers refilled.\nDemo document generated by DueDesk seeds.\n"}
          ],
          not has_document?.(noc, filename) do
        {:ok, _} =
          Documents.attach_documents(owner_scope, noc, role, [
            prepare.(owner_scope, filename, content)
          ])
      end
    end

    filename = "PTEC-payment-challan.pdf"

    with %DueItem{} = ptec <- find.("Professional tax (PTEC)"),
         false <- has_document?.(ptec, filename),
         %Cycle{} = closed <-
           Repo.one(
             from(c in Cycle,
               where: c.due_item_id == ^ptec.id and not is_nil(c.completed_at),
               order_by: [desc: c.sequence],
               limit: 1
             )
           ) do
      upload =
        prepare.(
          owner_scope,
          filename,
          pdf.([
            "Professional Tax Payment Challan",
            "Paid on the Mahakosh portal",
            "Demo document generated by DueDesk seeds"
          ])
        )

      {:ok, _} =
        Ecto.Multi.new()
        |> Documents.multi_attach(owner_scope, ptec, fn _ -> closed end, "completion", [upload])
        |> Repo.transaction()
    end
  end

  logins =
    Enum.reduce(accounts, logins, fn {plan, account_name, slug}, logins ->
      {owner, owner_pw} =
        ensure_user.(
          "#{String.capitalize(slug)} Owner",
          "#{slug}.owner@duedesk.local",
          "9876500001"
        )

      {admin, admin_pw} =
        ensure_user.(
          "#{String.capitalize(slug)} Admin",
          "#{slug}.admin@duedesk.local",
          "9876500002"
        )

      {member, member_pw} =
        ensure_user.(
          "#{String.capitalize(slug)} Staff",
          "#{slug}.user@duedesk.local",
          "9876500003"
        )

      account =
        case Tenancy.get_current_membership(owner) do
          %Membership{customer_account: account} ->
            account

          nil ->
            {:ok, %{customer_account: account}} =
              Tenancy.create_customer_account(Scope.for_user(owner), %{
                name: account_name,
                notification_mobile: owner.mobile_number,
                whatsapp_consent: plan != "free"
              })

            account
            |> Ecto.Changeset.change(
              plan_code: plan,
              billing_state: if(plan == "free", do: "free", else: "active_paid")
            )
            |> Repo.update!()
        end

      for {user, role} <- [{admin, "admin"}, {member, "user"}],
          is_nil(Repo.get_by(Membership, customer_account_id: account.id, user_id: user.id)) do
        %Membership{customer_account_id: account.id, user_id: user.id}
        |> Membership.changeset(%{role: role, status: "active"})
        |> Repo.insert!()
      end

      # The Entrepreneur account's User gets WhatsApp reminders.
      if plan == "entrepreneur" do
        from(m in Membership,
          where:
            m.customer_account_id == ^account.id and m.user_id == ^member.id and
              is_nil(m.whatsapp_consent_at)
        )
        |> Repo.update_all(
          set: [notify_whatsapp: true, whatsapp_consent_at: DateTime.utc_now(:second)]
        )
      end

      # A pending invitation on the paid accounts (Free has no seat left).
      # Its token is thrown away; use Resend on /users to get a working
      # link in /dev/mailbox.
      invitee = "#{slug}.invitee@duedesk.local"
      now = DateTime.utc_now(:second)

      if plan != "free" and
           not Repo.exists?(
             from(i in Invitation,
               where:
                 i.customer_account_id == ^account.id and i.email == ^invitee and
                   is_nil(i.accepted_at) and is_nil(i.revoked_at) and i.expires_at > ^now
             )
           ) do
        Repo.insert!(%Invitation{
          customer_account_id: account.id,
          email: invitee,
          role: "user",
          token_hash: :crypto.hash(:sha256, :crypto.strong_rand_bytes(32)),
          invited_by_user_id: owner.id,
          expires_at: DateTime.add(now, Invitation.validity_days(), :day)
        })
      end

      # Re-read the membership so the scope sees the updated plan.
      owner_scope =
        Scope.put_membership(Scope.for_user(owner), Tenancy.get_current_membership(owner))

      if Organisations.count_by_status(owner_scope) == %{active: 0, archived: 0} do
        for attrs <- Map.fetch!(organisations, slug) do
          {:ok, _} =
            Organisations.create_organisation(
              owner_scope,
              Map.put(attrs, :declaration_accepted, true)
            )
        end
      end

      seed_due_items.(owner_scope, admin, member)
      seed_lifecycle.(owner_scope, member)
      seed_documents.(owner_scope)

      label = "#{account_name} (#{plan})"

      logins ++
        [
          {"#{label} · Super Admin", owner.email, owner_pw},
          {"#{label} · Administrator", admin.email, admin_pw},
          {"#{label} · User", member.email, member_pw}
        ]
    end)

  IO.puts("\nDueDesk demo logins (dev only — shown once):\n")

  for {label, email, pw} <- logins do
    IO.puts("  #{String.pad_trailing(label, 48)} #{String.pad_trailing(email, 32)} #{pw}")
  end

  IO.puts("")
end
