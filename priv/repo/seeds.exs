# Demo data for local development:
#
#     mix run priv/repo/seeds.exs   (also run by mix ecto.setup / ecto.reset)
#
# Creates one operator and three Customer Accounts (Free, Business,
# Entrepreneur) with a Super Admin, an Administrator and a User each.
# Passwords are generated on every run and printed once to this console.
# Existing records are left alone, so running it twice is safe.
#
# Later phases add Organisations, DueItems in every status, documents and
# reminders here.

if Mix.env() != :dev do
  IO.puts("Seeds create demo logins and only run in the dev environment. Skipping.")
else
  alias DueDesk.{Accounts, Admin, Repo, Tenancy}
  alias DueDesk.Accounts.{Scope, User}
  alias DueDesk.Admin.Operator
  alias DueDesk.Tenancy.Membership

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
