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

    resources "/invoices", InvoiceController, only: [:index, :create, :show]
    post "/invoices/:id/payments", InvoiceController, :add_payment
    post "/invoices/:id/cancel", InvoiceController, :cancel

    get "/reports/sales_summary", ReportController, :sales_summary
    get "/reports/daily_sales", ReportController, :daily_sales
    get "/reports/top_products", ReportController, :top_products
    get "/reports/stock", ReportController, :stock
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
