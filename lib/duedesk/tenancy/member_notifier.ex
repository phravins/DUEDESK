defmodule DueDesk.Tenancy.MemberNotifier do
  @moduledoc """
  Emails about membership: invitations and role changes. Sent after the
  change has committed. The invitation link is only ever in the email,
  never in logs or audit rows.
  """
  import Swoosh.Email

  alias DueDesk.Mailer
  alias DueDesk.Tenancy.Membership

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(Application.fetch_env!(:duedesk, :mail_from))
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc "Invites `invitation.email` to the account, with the accept `url`."
  def deliver_invitation(invitation, account, inviter, url) do
    role = Membership.role_label(invitation.role)

    deliver(invitation.email, "#{inviter.name} invited you to #{account.name} on DueDesk", """
    Hi,

    #{inviter.name} has invited you to join #{account.name} on DueDesk as #{article(role)} #{role}.

    DueDesk keeps track of renewals, filings and other obligations that fall due, and reminds the right people before they become overdue.

    Accept the invitation here:

    #{url}

    This link expires in #{DueDesk.Tenancy.Invitation.validity_days()} days. If you were not expecting it, you can ignore this email.

    — DueDesk
    """)
  end

  @doc "Tells a member their role in the account has changed."
  def deliver_role_changed(user, account, role, changed_by) do
    label = Membership.role_label(role)

    deliver(user.email, "Your role in #{account.name} is now #{label}", """
    Hi #{user.name},

    #{changed_by.name} changed your role in #{account.name} on DueDesk to #{label}.

    #{role_summary(role)}

    — DueDesk
    """)
  end

  defp role_summary("super_admin"),
    do:
      "As a Super Admin you manage the account, its plan and billing, and its Administrators and Users."

  defp role_summary("admin"),
    do: "As an Administrator you see every DueItem of the account and manage its Users."

  defp role_summary("user"),
    do: "As a User you see the DueItems you are responsible for or assigned to."

  defp article("Administrator"), do: "an"
  defp article(_), do: "a"
end
