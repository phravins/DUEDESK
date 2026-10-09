defmodule DueDeskWeb.PageHTML do
  @moduledoc """
  The public terms of service and privacy policy, linked from the sign-up,
  log-in and invitation forms. Open to everyone, logged in or not.
  """
  use DueDeskWeb, :html

  # The date the texts below last changed.
  defp updated, do: ~D[2026-10-09]

  def terms(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope} document>
      <article id="terms">
        <.auth_heading
          eyebrow="DueDesk"
          title="Terms of service"
          tagline={"Updated #{DueDeskWeb.Format.date(updated())}"}
        />

        <.legal_section title="1. The service">
          DueDesk helps businesses keep track of renewals, filings, licences and other
          obligations that fall due, and reminds the right people before they become overdue.
          These terms apply to everyone who creates or joins a DueDesk account.
        </.legal_section>

        <.legal_section title="2. Your account">
          The person who creates a DueDesk account becomes its Super Admin and is responsible
          for who is invited, the role each person has, and the plan the account is on. Keep
          your password private and tell us straight away if you think someone else has used
          your login.
        </.legal_section>

        <.legal_section title="3. Your data">
          The DueItems, organisations, documents and notes you add belong to your account. We
          use them only to run DueDesk for you. You are responsible for having the right to
          upload what you add, and for its accuracy.
        </.legal_section>

        <.legal_section title="4. Reminders are an aid">
          DueDesk sends reminders by email and, when you turn it on, WhatsApp. Reminders help
          but do not replace your own checks: you remain responsible for meeting every
          obligation on time, including when a message is delayed or not delivered.
        </.legal_section>

        <.legal_section title="5. Plans and payment">
          The Free plan costs nothing and has no time limit. Paid plans are billed monthly or
          yearly in advance. Each plan differs only in capacity; going over a limit stops new
          additions but never deletes what you already have, including after a downgrade.
        </.legal_section>

        <.legal_section title="6. Acceptable use">
          Do not use DueDesk to store unlawful content, to try to reach other accounts' data,
          to disrupt the service, or to send messages people have not agreed to receive.
        </.legal_section>

        <.legal_section title="7. Closing an account">
          A Super Admin can close the account at any time. We may suspend an account that
          breaks these terms, and will tell the Super Admin why.
        </.legal_section>

        <.legal_section title="8. Changes">
          We may update these terms. When a change matters, we will tell Super Admins by email
          before it takes effect.
        </.legal_section>

        <.legal_footer other={~p"/privacy"} other_label="Privacy policy" />
      </article>
    </Layouts.auth>
    """
  end

  def privacy(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope} document>
      <article id="privacy">
        <.auth_heading
          eyebrow="DueDesk"
          title="Privacy policy"
          tagline={"Updated #{DueDeskWeb.Format.date(updated())}"}
        />

        <.legal_section title="1. What we collect">
          Your name, email address and mobile number; the account details you enter, such as
          organisations, DueItems, dates and documents; and basic technical records, such as
          log-in times, needed to keep the service secure.
        </.legal_section>

        <.legal_section title="2. How we use it">
          Only to run DueDesk: to let you log in, show your account's information to the people
          in it, send the reminders and notifications you set up, process payments, and keep a
          history of important changes. We do not sell your data or use it for advertising.
        </.legal_section>

        <.legal_section title="3. Who can see it">
          Each account's data is kept separate. Inside an account, Super Admins and
          Administrators see every DueItem; Users see the DueItems they are responsible for or
          assigned to. Our staff access an account only to support it or keep it secure.
        </.legal_section>

        <.legal_section title="4. Services we rely on">
          We use trusted providers to host DueDesk, store documents, deliver email and WhatsApp
          messages and take payments. They handle data only on our instructions. Card details
          are entered with the payment provider and never stored by DueDesk.
        </.legal_section>

        <.legal_section title="5. WhatsApp">
          WhatsApp reminders are sent only after you turn them on and give consent in your
          settings. You can turn them off at any time.
        </.legal_section>

        <.legal_section title="6. Security and retention">
          Connections are encrypted, documents are stored privately and opened through
          short-lived links, and passwords are stored only as secure hashes. Data stays while
          the account is open; after an account is closed it is deleted, except where the law
          requires us to keep records.
        </.legal_section>

        <.legal_section title="7. Your choices">
          You can update your name, email, mobile number and notification settings from your
          settings at any time, and ask us for a copy of your data or for it to be deleted.
        </.legal_section>

        <.legal_footer other={~p"/terms"} other_label="Terms of service" />
      </article>
    </Layouts.auth>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp legal_section(assigns) do
    ~H"""
    <section class="mb-6">
      <h2 class="mb-1.5 text-[14px] font-semibold text-ink">{@title}</h2>
      <p class="text-[13.5px] leading-relaxed text-zinc-600">{render_slot(@inner_block)}</p>
    </section>
    """
  end

  attr :other, :string, required: true
  attr :other_label, :string, required: true

  defp legal_footer(assigns) do
    ~H"""
    <div class="mt-10 flex items-center justify-between border-t border-line pt-5 text-[13px]">
      <.link
        href={@other}
        class="font-medium text-zinc-700 underline underline-offset-2 hover:text-brand"
      >
        {@other_label}
      </.link>
      <.link href={~p"/"} class="font-medium text-brand hover:underline">Go to DueDesk</.link>
    </div>
    """
  end
end
