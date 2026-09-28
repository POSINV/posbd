defmodule Posbd.WhatsappTest do
  use Posbd.DataCase, async: true

  alias Posbd.Whatsapp
  alias Posbd.Whatsapp.{SendMessageWorker, WhatsappMessage}

  import Posbd.BusinessesFixtures
  import Posbd.CustomersFixtures
  import Posbd.SubscriptionsFixtures
  import Posbd.WhatsappFixtures

  setup do
    %{scope: full_scope_fixture()}
  end

  describe "create_template/2 and update_template/3" do
    test "always starts pending_approval, even if the client tries to set another status", %{
      scope: scope
    } do
      assert {:ok, template} =
               Whatsapp.create_template(scope, valid_template_attrs(%{"status" => "approved"}))

      assert template.status == "pending_approval"
      assert template.variable_count == 3
    end

    test "editing content resubmits a previously-approved template", %{scope: scope} do
      template = approved_template_fixture(scope)
      assert template.status == "approved"

      assert {:ok, updated} = Whatsapp.update_template(scope, template, %{"body" => "New body"})
      assert updated.status == "pending_approval"
    end
  end

  describe "platform-admin review" do
    test "approve_template records the provider name and reviewer", %{scope: scope} do
      template = template_fixture(scope)
      admin = platform_admin_fixture()

      assert {:ok, approved} = Whatsapp.approve_template(admin, template, "bill_ready_v1")
      assert approved.status == "approved"
      assert approved.provider_template_name == "bill_ready_v1"
      assert approved.reviewed_by_id == admin.id
    end

    test "reject_template records a reason", %{scope: scope} do
      template = template_fixture(scope)
      admin = platform_admin_fixture()

      assert {:ok, rejected} =
               Whatsapp.reject_template(admin, template, "Contains promotional language")

      assert rejected.status == "rejected"
      assert rejected.rejected_reason == "Contains promotional language"
    end

    test "list_templates_for_review defaults to pending_approval", %{scope: scope} do
      pending = template_fixture(scope)
      approved = approved_template_fixture(scope)

      ids = Whatsapp.list_templates_for_review() |> Enum.map(& &1.id)
      assert pending.id in ids
      refute approved.id in ids
    end
  end

  describe "notify_invoice_created/2" do
    test "queues a message and enqueues the send job when a billing template is approved", %{
      scope: scope
    } do
      approved_template_fixture(scope)
      customer = customer_fixture(scope)

      invoice = %{
        customer: customer,
        invoice_number: "INV-000001",
        currency: "INR",
        total_amount: Decimal.new("250.00"),
        loyalty_points_earned: 0
      }

      assert {:ok, message} = Whatsapp.notify_invoice_created(scope.business, invoice)
      assert message.status == "queued"
      assert message.body == "Hi #{customer.name}, your bill INV-000001 for INR 250.00 is ready."

      assert_enqueued(worker: SendMessageWorker, args: %{"message_id" => message.id})
    end

    test "skips silently when there is no approved billing template", %{scope: scope} do
      customer = customer_fixture(scope)

      invoice = %{
        customer: customer,
        invoice_number: "INV-1",
        currency: "INR",
        total_amount: Decimal.new("10"),
        loyalty_points_earned: 0
      }

      assert {:skip, :not_applicable} = Whatsapp.notify_invoice_created(scope.business, invoice)
      refute Repo.exists?(WhatsappMessage)
    end

    test "skips when the customer has opted out of transactional messages", %{scope: scope} do
      approved_template_fixture(scope)
      customer = customer_fixture(scope, accepts_transactional_messages: false)

      invoice = %{
        customer: customer,
        invoice_number: "INV-1",
        currency: "INR",
        total_amount: Decimal.new("10"),
        loyalty_points_earned: 0
      }

      assert {:skip, :opted_out} = Whatsapp.notify_invoice_created(scope.business, invoice)
      refute_enqueued(worker: SendMessageWorker)
    end

    test "skips a walk-in sale with no customer", %{scope: scope} do
      approved_template_fixture(scope)

      invoice = %{
        customer: nil,
        invoice_number: "INV-1",
        currency: "INR",
        total_amount: Decimal.new("10"),
        loyalty_points_earned: 0
      }

      assert {:skip, :not_applicable} = Whatsapp.notify_invoice_created(scope.business, invoice)
    end
  end

  describe "notify_loyalty_earned/2" do
    test "only sends when points were actually earned on this bill", %{scope: scope} do
      approved_template_fixture(scope, %{
        "purpose" => "loyalty",
        "body" => "You earned {{2}} points, {{1}}!"
      })

      customer = customer_fixture(scope)

      zero_invoice = %{customer: customer, loyalty_points_earned: 0}

      assert {:skip, :not_applicable} =
               Whatsapp.notify_loyalty_earned(scope.business, zero_invoice)

      earned_invoice = %{customer: customer, loyalty_points_earned: 5}
      assert {:ok, message} = Whatsapp.notify_loyalty_earned(scope.business, earned_invoice)
      assert message.kind == "transactional"
    end
  end

  describe "campaigns" do
    test "create_campaign requires the business's own approved template", %{scope: scope} do
      other_business_template = approved_template_fixture(full_scope_fixture())

      assert {:error, %{message: message}} =
               Whatsapp.create_campaign(scope, %{
                 "name" => "Diwali Offer",
                 "audience_segment" => "all",
                 "template_id" => other_business_template.id
               })

      assert message =~ "not found"

      pending = template_fixture(scope)

      assert {:error, %{message: message}} =
               Whatsapp.create_campaign(scope, %{
                 "name" => "Diwali Offer",
                 "audience_segment" => "all",
                 "template_id" => pending.id
               })

      assert message =~ "not approved"
    end

    test "schedule_campaign with no time dispatches immediately", %{scope: scope} do
      template =
        approved_template_fixture(scope, %{
          "purpose" => "offer",
          "body" => "Hi {{1}}, 20%% off today!"
        })

      {:ok, campaign} =
        Whatsapp.create_campaign(scope, %{
          "name" => "Flash Sale",
          "audience_segment" => "all",
          "template_id" => template.id
        })

      assert campaign.status == "draft"
      assert {:ok, sent} = Whatsapp.schedule_campaign(scope, campaign)
      assert sent.status == "sent"

      assert_enqueued(
        worker: Posbd.Whatsapp.CampaignDispatchWorker,
        args: %{"campaign_id" => campaign.id}
      )
    end

    test "schedule_campaign with a future time marks it scheduled", %{scope: scope} do
      template = approved_template_fixture(scope, %{"purpose" => "offer"})

      {:ok, campaign} =
        Whatsapp.create_campaign(scope, %{
          "name" => "Flash Sale",
          "audience_segment" => "all",
          "template_id" => template.id
        })

      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
      assert {:ok, scheduled} = Whatsapp.schedule_campaign(scope, campaign, future)
      assert scheduled.status == "scheduled"
      assert DateTime.compare(scheduled.scheduled_at, future) == :eq
    end

    test "cancel_campaign works from draft/scheduled but not from sent", %{scope: scope} do
      template = approved_template_fixture(scope, %{"purpose" => "offer"})

      {:ok, campaign} =
        Whatsapp.create_campaign(scope, %{
          "name" => "Flash Sale",
          "audience_segment" => "all",
          "template_id" => template.id
        })

      assert {:ok, cancelled} = Whatsapp.cancel_campaign(scope, campaign)
      assert cancelled.status == "cancelled"

      {:ok, sent} = Whatsapp.schedule_campaign(scope, campaign)
      assert {:error, %{message: message}} = Whatsapp.cancel_campaign(scope, sent)
      assert message =~ "already been sent"
    end

    test "dispatch_campaign only reaches customers who opted into promotional messages", %{
      scope: scope
    } do
      template = approved_template_fixture(scope, %{"purpose" => "offer", "body" => "Hi {{1}}!"})
      opted_in = customer_fixture(scope, accepts_promotional_messages: true)
      opted_out = customer_fixture(scope, accepts_promotional_messages: false)

      {:ok, campaign} =
        Whatsapp.create_campaign(scope, %{
          "name" => "Flash Sale",
          "audience_segment" => "all",
          "template_id" => template.id
        })

      assert :ok = Whatsapp.dispatch_campaign(campaign.id)

      messages = Repo.all(WhatsappMessage)
      assert [message] = messages
      assert message.customer_id == opted_in.id
      assert message.campaign_id == campaign.id
      refute Enum.any?(messages, &(&1.customer_id == opted_out.id))
    end

    test "a customer already sent a promotional message recently is skipped by a second campaign (Phase 2 §34)",
         %{
           scope: scope
         } do
      template = approved_template_fixture(scope, %{"purpose" => "offer", "body" => "Hi {{1}}!"})
      customer_fixture(scope, accepts_promotional_messages: true)

      {:ok, first_campaign} =
        Whatsapp.create_campaign(scope, %{
          "name" => "First",
          "audience_segment" => "all",
          "template_id" => template.id
        })

      assert :ok = Whatsapp.dispatch_campaign(first_campaign.id)
      assert [_first] = Repo.all(WhatsappMessage)

      {:ok, second_campaign} =
        Whatsapp.create_campaign(scope, %{
          "name" => "Second",
          "audience_segment" => "all",
          "template_id" => template.id
        })

      assert :ok = Whatsapp.dispatch_campaign(second_campaign.id)
      assert [_still_just_one] = Repo.all(WhatsappMessage)
    end

    test "campaign_stats/2 breaks down messages by status", %{scope: scope} do
      template = approved_template_fixture(scope, %{"purpose" => "offer"})
      customer_fixture(scope, accepts_promotional_messages: true)

      {:ok, campaign} =
        Whatsapp.create_campaign(scope, %{
          "name" => "Flash Sale",
          "audience_segment" => "all",
          "template_id" => template.id
        })

      :ok = Whatsapp.dispatch_campaign(campaign.id)

      assert Whatsapp.campaign_stats(scope, campaign) == %{
               queued: 1,
               sent: 0,
               delivered: 0,
               read: 0,
               failed: 0,
               total: 1
             }
    end
  end

  describe "process_status_update/2" do
    test "updates the matching message and is a no-op for an unknown id", %{scope: scope} do
      approved_template_fixture(scope)
      customer = customer_fixture(scope)

      {:ok, message} =
        Whatsapp.notify_invoice_created(scope.business, %{
          customer: customer,
          invoice_number: "INV-1",
          currency: "INR",
          total_amount: Decimal.new("10"),
          loyalty_points_earned: 0
        })

      message = message |> WhatsappMessage.sent_changeset("wamid.XYZ") |> Repo.update!()

      assert :ok = Whatsapp.process_status_update("wamid.XYZ", "delivered")
      assert Repo.get(WhatsappMessage, message.id).status == "delivered"

      assert :ok = Whatsapp.process_status_update("wamid.does-not-exist", "read")
    end
  end
end
