defmodule DueDesk.Accounts.UserNotifier do
  import Swoosh.Email

  alias DueDesk.Mailer

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

  @doc """
  Deliver instructions to confirm the email address after sign up.
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirm your DueDesk email address", """
    Hi #{user.name},

    Welcome to DueDesk. Please confirm your email address by visiting the link below:

    #{url}

    This link expires in 7 days. If you didn't create a DueDesk account, you can ignore this email.

    — DueDesk
    """)
  end

  @doc """
  Deliver instructions to reset the password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset your DueDesk password", """
    Hi #{user.name},

    You can reset your DueDesk password by visiting the link below:

    #{url}

    This link expires in 2 hours. If you didn't request a password reset, you can ignore this email.

    — DueDesk
    """)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Confirm your new DueDesk email address", """
    Hi #{user.name},

    You can change your DueDesk email address by visiting the link below:

    #{url}

    If you didn't request this change, please ignore this email.

    — DueDesk
    """)
  end
end
