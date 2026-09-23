defmodule PosbdWeb.Api.BusinessJSON do
  alias Posbd.Businesses.Business

  def index(%{businesses: businesses}) do
    %{data: Enum.map(businesses, fn {business, role} -> business_summary(business, role) end)}
  end

  def templates(%{templates: templates}) do
    %{data: templates}
  end

  def show(%{business: business, role: role}) do
    %{data: business_detail(business, role)}
  end

  def business_summary(%Business{} = business, role) do
    %{
      id: business.id,
      name: business.name,
      slug: business.slug,
      business_type: business.business_type,
      currency: business.currency,
      role: role,
      onboarding_completed: not is_nil(business.onboarding_completed_at)
    }
  end

  defp business_detail(%Business{} = business, role) do
    %{
      id: business.id,
      name: business.name,
      slug: business.slug,
      business_type: business.business_type,
      country: business.country,
      currency: business.currency,
      timezone: business.timezone,
      language: business.language,
      date_format: business.date_format,
      invoice_prefix: business.invoice_prefix,
      address: business.address,
      phone: business.phone,
      email: business.email,
      tax_number: business.tax_number,
      invoice_footer: business.invoice_footer,
      invoice_terms: business.invoice_terms,
      printer_paper_width: business.printer_paper_width,
      printer_header_align: business.printer_header_align,
      printer_font_size: business.printer_font_size,
      default_print_layout: business.default_print_layout,
      settings: business.settings,
      role: role,
      onboarding_completed: not is_nil(business.onboarding_completed_at),
      inserted_at: business.inserted_at
    }
  end
end
