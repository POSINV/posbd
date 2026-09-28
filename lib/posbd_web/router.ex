defmodule PosbdWeb.Router do
  use PosbdWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PosbdWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_auth do
    plug PosbdWeb.Plugs.ApiAuth
  end

  pipeline :api_business do
    plug PosbdWeb.Plugs.RequireBusiness
  end

  pipeline :subscription_gate do
    plug PosbdWeb.Plugs.SubscriptionGate
  end

  pipeline :api_platform_admin do
    plug PosbdWeb.Plugs.PlatformAdminAuth
  end

  scope "/", PosbdWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Public API routes (no auth required)
  scope "/api/v1", PosbdWeb.Api do
    pipe_through :api

    post "/auth/register", AuthController, :register
    post "/auth/login", AuthController, :login
    get "/business_types", BusinessController, :templates
    get "/subscription_plans", SubscriptionController, :public_plans

    post "/admin/login", Admin.SessionController, :login

    # Razorpay calls this directly with no user session - authenticated
    # by its own signature header instead (Phase 2 §11), verified inside
    # the controller.
    post "/webhooks/razorpay", RazorpayWebhookController, :create

    # Meta's WhatsApp webhook: a one-time GET handshake to subscribe, then
    # POST status callbacks - both unauthenticated at the router level,
    # verified inside the controller (Phase 2 §27).
    get "/webhooks/whatsapp", WhatsappWebhookController, :verify
    post "/webhooks/whatsapp", WhatsappWebhookController, :create
  end

  # Authenticated API routes, not yet scoped to a specific business
  scope "/api/v1", PosbdWeb.Api do
    pipe_through [:api, :api_auth]

    delete "/auth/logout", AuthController, :logout
    get "/me", AuthController, :me

    get "/businesses", BusinessController, :index
    post "/businesses", BusinessController, :create
    get "/businesses/:id", BusinessController, :show
    patch "/businesses/:id", BusinessController, :update
    post "/businesses/:id/complete_onboarding", BusinessController, :complete_onboarding
  end

  # Tenant-scoped API routes (require x-business-id header + membership).
  # Future modules (products, inventory, billing, ...) mount here.
  scope "/api/v1", PosbdWeb.Api do
    pipe_through [:api, :api_auth, :api_business]

    # Deliberately outside the :subscription_gate below - a business whose
    # trial/subscription has lapsed must still be able to see its status
    # and payment history in order to fix it (Phase 2 §9).
    get "/subscription", SubscriptionController, :show
    get "/subscription/payments", SubscriptionController, :payments
    post "/subscription/checkout", SubscriptionController, :create_checkout
    post "/subscription/checkout/verify", SubscriptionController, :verify_checkout

    scope "/" do
      pipe_through :subscription_gate

      resources "/categories", CategoryController, except: [:new, :edit]

      resources "/products", ProductController, except: [:new, :edit] do
        resources "/variants", ProductVariantController, only: [:create, :update, :delete]
      end

      get "/attributes", AttributeController, :index

      get "/price_tiers/quote", PriceTierController, :quote
      resources "/price_tiers", PriceTierController, only: [:index, :create, :update, :delete]

      get "/inventory/movements", InventoryController, :index
      post "/inventory/movements", InventoryController, :create

      resources "/customers", CustomerController, except: [:new, :edit]
      get "/customers/:id/summary", CustomerController, :summary
      get "/customers/:id/loyalty", LoyaltyController, :ledger

      get "/loyalty/program", LoyaltyController, :show_program
      patch "/loyalty/program", LoyaltyController, :update_program

      resources "/invoices", InvoiceController, only: [:index, :create, :show]
      post "/invoices/:id/payments", InvoiceController, :add_payment
      post "/invoices/:id/cancel", InvoiceController, :cancel

      get "/imports/products/template", ImportController, :products_template
      post "/imports/products/preview", ImportController, :preview_products
      post "/imports/products/commit", ImportController, :commit_products
      get "/imports/opening_stock/template", ImportController, :opening_stock_template
      post "/imports/opening_stock/preview", ImportController, :preview_opening_stock
      post "/imports/opening_stock/commit", ImportController, :commit_opening_stock
      get "/imports/historical_bills/template", ImportController, :historical_bills_template
      post "/imports/historical_bills/preview", ImportController, :preview_historical_bills
      post "/imports/historical_bills/commit", ImportController, :commit_historical_bills
      get "/imports/history", ImportController, :history

      get "/audit_logs", AuditLogController, :index

      get "/reports/sales_summary", ReportController, :sales_summary
      get "/reports/daily_sales", ReportController, :daily_sales
      get "/reports/top_products", ReportController, :top_products
      get "/reports/stock", ReportController, :stock
      get "/reports/loyalty", ReportController, :loyalty

      resources "/whatsapp/templates", WhatsappTemplateController,
        only: [:index, :create, :show, :update]

      resources "/whatsapp/campaigns", WhatsappCampaignController, only: [:index, :create, :show]
      post "/whatsapp/campaigns/:id/cancel", WhatsappCampaignController, :cancel
      get "/whatsapp/messages", WhatsappMessageController, :index

      resources "/offers", OfferController, only: [:index, :create, :show, :update]
    end
  end

  # Platform-admin API routes (Phase 2 §13/§45) - entirely separate auth
  # domain from tenant users; never reachable with a business bearer token.
  scope "/api/v1/admin", PosbdWeb.Api.Admin do
    pipe_through [:api, :api_platform_admin]

    get "/me", SessionController, :me
    delete "/logout", SessionController, :logout

    get "/dashboard", DashboardController, :show
    get "/businesses", DashboardController, :businesses

    post "/businesses/:business_id/activate_plan", SubscriptionController, :activate_plan
    post "/businesses/:business_id/cancel_subscription", SubscriptionController, :cancel

    get "/plans", PlanController, :index
    post "/plans", PlanController, :create
    patch "/plans/:id", PlanController, :update

    get "/whatsapp/templates", WhatsappTemplateController, :index
    post "/whatsapp/templates/:id/approve", WhatsappTemplateController, :approve
    post "/whatsapp/templates/:id/reject", WhatsappTemplateController, :reject
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:posbd, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PosbdWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
